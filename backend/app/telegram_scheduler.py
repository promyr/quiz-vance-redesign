"""Persistent scheduling and routing for Quiz Vance Telegram community posts."""

from __future__ import annotations

import logging
import threading
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from typing import Any

from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session

from . import models, telegram_bot
from .database import SessionLocal

logger = logging.getLogger(__name__)
_TELEGRAM_AUTO_POST_LOCK = threading.Lock()
_TELEGRAM_AUTO_POST_STOP = threading.Event()
_TELEGRAM_AUTO_POST_THREAD: threading.Thread | None = None


@dataclass(frozen=True)
class _TelegramAutoPostTarget:
    chat_id: int | str
    chat_id_storage: str
    message_thread_id: int | None


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _parse_chat_id(raw: str | int | None) -> int | str | None:
    value = str(raw or "").strip()
    if not value:
        return None
    if value.lstrip("-").isdigit():
        return int(value)
    return value


def _load_telegram_community_config(
    db: Session,
) -> models.TelegramCommunityConfig | None:
    return (
        db.query(models.TelegramCommunityConfig)
        .order_by(models.TelegramCommunityConfig.id.asc())
        .first()
    )


def _resolve_telegram_topic_thread_id(
    row: models.TelegramCommunityConfig | None,
    topic_key: str,
) -> int | None:
    fallback_thread = telegram_bot.community_updates_thread_id()
    if row is None:
        return fallback_thread
    thread_map = {
        "atualizacoes": row.atualizacoes_thread_id,
        "comece_aqui": row.comece_aqui_thread_id,
        "bate_papo": row.bate_papo_thread_id,
        "resultados": row.resultados_thread_id,
        "suporte": row.suporte_thread_id,
        "feedbacks": row.feedbacks_thread_id,
    }
    raw_thread_id = (
        thread_map.get(str(topic_key or "").strip().lower())
        or row.atualizacoes_thread_id
    )
    try:
        thread_id = int(raw_thread_id or 0)
    except (TypeError, ValueError):
        thread_id = 0
    if thread_id > 0:
        return thread_id
    return fallback_thread


def _extract_telegram_group_observation(
    update: dict[str, object] | None,
) -> tuple[int | str | None, int | None]:
    if not isinstance(update, dict):
        return None, None

    candidates: list[dict[str, Any]] = []
    message = update.get("message")
    if isinstance(message, dict):
        candidates.append(message)
    callback = update.get("callback_query")
    if isinstance(callback, dict):
        callback_message = callback.get("message")
        if isinstance(callback_message, dict):
            candidates.append(callback_message)

    for item in candidates:
        chat = item.get("chat") if isinstance(item.get("chat"), dict) else {}
        chat_type = str(chat.get("type") or "").strip().lower()
        if chat_type not in {"group", "supergroup"}:
            continue
        chat_id = chat.get("id")
        if chat_id is None:
            continue
        try:
            thread_id = int(item.get("message_thread_id") or 0)
        except (TypeError, ValueError):
            thread_id = 0
        return chat_id, (thread_id if thread_id > 0 else None)
    return None, None


def _remember_telegram_group_target_from_update(
    db: Session, update: dict[str, object] | None
) -> bool:
    chat_id, thread_id = _extract_telegram_group_observation(update)
    if chat_id is None:
        return False

    current = _load_telegram_community_config(db)
    normalized = telegram_bot.normalize_chat_id(chat_id)
    changed = False

    if current is None:
        current = _persist_telegram_community_config(db, chat_id, [])
        changed = True

    if str(current.chat_id or "").strip() != normalized:
        current.chat_id = normalized
        changed = True

    if int(thread_id or 0) > 0 and int(current.atualizacoes_thread_id or 0) <= 0:
        current.atualizacoes_thread_id = int(thread_id)
        changed = True

    if changed:
        current.updated_at = _utc_now()
        db.commit()
        db.refresh(current)
    return changed


def _persist_telegram_community_config(
    db: Session,
    chat_id: int | str,
    topics: list[dict[str, object]] | None = None,
) -> models.TelegramCommunityConfig:
    topic_map: dict[str, int] = {}
    for topic in topics or []:
        if not isinstance(topic, dict):
            continue
        key = str(topic.get("key") or "").strip().lower()
        try:
            thread_id = int(topic.get("message_thread_id") or 0)
        except (TypeError, ValueError):
            thread_id = 0
        if key and thread_id > 0:
            topic_map[key] = thread_id

    row = _load_telegram_community_config(db)
    if row is None:
        row = models.TelegramCommunityConfig(
            chat_id=telegram_bot.normalize_chat_id(chat_id)
        )
        db.add(row)

    row.chat_id = telegram_bot.normalize_chat_id(chat_id)
    row.atualizacoes_thread_id = (
        topic_map.get("atualizacoes") or row.atualizacoes_thread_id
    )
    row.comece_aqui_thread_id = (
        topic_map.get("comece_aqui") or row.comece_aqui_thread_id
    )
    row.bate_papo_thread_id = topic_map.get("bate_papo") or row.bate_papo_thread_id
    row.resultados_thread_id = topic_map.get("resultados") or row.resultados_thread_id
    row.suporte_thread_id = topic_map.get("suporte") or row.suporte_thread_id
    row.feedbacks_thread_id = topic_map.get("feedbacks") or row.feedbacks_thread_id
    row.updated_at = _utc_now()
    db.commit()
    db.refresh(row)
    return row


def _resolve_telegram_auto_post_target(
    db: Session, topic_key: str
) -> _TelegramAutoPostTarget | None:
    row = _load_telegram_community_config(db)
    if row is not None:
        chat_id_storage = str(row.chat_id or "").strip()
        parsed_chat_id = _parse_chat_id(chat_id_storage)
        if parsed_chat_id is not None:
            return _TelegramAutoPostTarget(
                chat_id=parsed_chat_id,
                chat_id_storage=chat_id_storage,
                message_thread_id=_resolve_telegram_topic_thread_id(row, topic_key),
            )

    env_chat_id = telegram_bot.community_chat_id()
    if env_chat_id is None:
        return None
    return _TelegramAutoPostTarget(
        chat_id=env_chat_id,
        chat_id_storage=telegram_bot.normalize_chat_id(env_chat_id),
        message_thread_id=telegram_bot.community_updates_thread_id(),
    )


def _find_telegram_post_row(
    db: Session, *, log_model, day_key: date, slot_key: str = ""
) -> Any | None:
    query = db.query(log_model).filter(log_model.day_key == day_key)
    if hasattr(log_model, "slot_key"):
        query = query.filter(log_model.slot_key == str(slot_key or "default"))
    return query.first()


def _acquire_telegram_post_slot(
    db: Session,
    *,
    log_model,
    day_key: date,
    slot_key: str = "",
    default_topic_key: str,
    topic_key: str,
    target: _TelegramAutoPostTarget,
    post_text: str,
    now_utc: datetime,
) -> Any | None:
    retry_after = timedelta(minutes=telegram_bot.auto_post_retry_minutes())
    row = _find_telegram_post_row(
        db, log_model=log_model, day_key=day_key, slot_key=slot_key
    )
    if row is None:
        row_kwargs = {
            "day_key": day_key,
            "topic_key": str(topic_key or default_topic_key),
            "chat_id": target.chat_id_storage,
            "message_thread_id": target.message_thread_id,
            "post_text": str(post_text or ""),
            "status": "sending",
            "attempt_count": 1,
            "last_attempt_at": now_utc,
            "last_error": None,
            "created_at": now_utc,
            "updated_at": now_utc,
        }
        if hasattr(log_model, "slot_key"):
            row_kwargs["slot_key"] = str(slot_key or "default")
        row = log_model(**row_kwargs)
        db.add(row)
        try:
            db.commit()
            db.refresh(row)
            return row
        except IntegrityError:
            db.rollback()
            row = _find_telegram_post_row(
                db, log_model=log_model, day_key=day_key, slot_key=slot_key
            )

    if row is None or row.sent_at is not None:
        return None

    last_attempt_at = row.last_attempt_at
    if isinstance(last_attempt_at, datetime) and last_attempt_at.tzinfo is None:
        last_attempt_at = last_attempt_at.replace(tzinfo=timezone.utc)
    if (
        isinstance(last_attempt_at, datetime)
        and (now_utc - last_attempt_at) < retry_after
    ):
        return None

    if hasattr(row, "slot_key"):
        row.slot_key = str(slot_key or getattr(row, "slot_key", "default") or "default")
    row.topic_key = str(topic_key or row.topic_key or default_topic_key)
    row.chat_id = target.chat_id_storage
    row.message_thread_id = target.message_thread_id
    row.post_text = str(post_text or row.post_text or "")
    row.status = "sending"
    row.attempt_count = max(0, int(row.attempt_count or 0)) + 1
    row.last_attempt_at = now_utc
    row.last_error = None
    row.updated_at = now_utc
    db.commit()
    db.refresh(row)
    return row


def _update_telegram_post_log(
    log_id: int,
    *,
    log_model,
    status: str,
    session_factory=None,
    error: str = "",
) -> None:
    session_maker = session_factory or SessionLocal
    db = session_maker()
    try:
        row = db.query(log_model).filter(log_model.id == int(log_id or 0)).first()
        if row is None:
            return
        now_utc = _utc_now()
        row.status = str(status or "pending")
        row.updated_at = now_utc
        if row.status == "sent":
            row.sent_at = now_utc
            row.last_error = None
        else:
            row.last_error = telegram_bot.sanitize_error(error)
        db.commit()
    except SQLAlchemyError:
        db.rollback()
    finally:
        db.close()


def _coerce_local_schedule_time(now_local: datetime | None) -> datetime:
    local_tz = telegram_bot.auto_post_zoneinfo()
    current_local = now_local or datetime.now(local_tz)
    if current_local.tzinfo is None:
        return current_local.replace(tzinfo=local_tz)
    return current_local.astimezone(local_tz)


def _resolve_instruction_due_slot_key(current_local: datetime) -> str:
    current_minutes = (current_local.hour * 60) + current_local.minute
    due_slot = ""
    for hour, minute in telegram_bot.instruction_post_times():
        scheduled_minutes = (hour * 60) + minute
        if current_minutes >= scheduled_minutes:
            due_slot = f"{hour:02d}:{minute:02d}"
    return due_slot


def _resolve_auto_post_due_slot_key(current_local: datetime) -> str:
    current_minutes = (current_local.hour * 60) + current_local.minute
    due_slot = ""
    for hour, minute in telegram_bot.auto_post_times():
        scheduled_minutes = (hour * 60) + minute
        if current_minutes >= scheduled_minutes:
            due_slot = f"{hour:02d}:{minute:02d}"
    return due_slot


def _send_telegram_community_post(
    client: telegram_bot.TelegramBotClient,
    target: _TelegramAutoPostTarget,
    post: telegram_bot.DailyCommunityPost,
) -> dict[str, Any]:
    if str(post.image_path or "").strip():
        return client.send_photo(
            target.chat_id,
            post.image_path,
            caption=post.text,
            message_thread_id=target.message_thread_id,
            reply_markup=telegram_bot.default_reply_markup(),
            disable_notification=False,
        )
    return client.send_message(
        target.chat_id,
        post.text,
        message_thread_id=target.message_thread_id,
        reply_markup=telegram_bot.default_reply_markup(),
        disable_notification=False,
    )


def _run_telegram_daily_auto_post_once(
    *, session_factory=None, now_local: datetime | None = None
) -> bool:
    if not telegram_bot.auto_post_enabled() or not telegram_bot.telegram_enabled():
        return False

    current_local = _coerce_local_schedule_time(now_local)
    due_slot_key = _resolve_auto_post_due_slot_key(current_local)
    if not due_slot_key:
        return False

    session_maker = session_factory or SessionLocal
    day_key = current_local.date()
    post = telegram_bot.build_automated_daily_post(day_key, due_slot_key)
    now_utc = _utc_now()
    log_id = 0
    target: _TelegramAutoPostTarget | None = None

    db = session_maker()
    try:
        target = _resolve_telegram_auto_post_target(db, post.topic_key)
        if target is None:
            return False
        row = _acquire_telegram_post_slot(
            db,
            log_model=models.TelegramDailyPostLog,
            day_key=day_key,
            slot_key=due_slot_key,
            default_topic_key="atualizacoes",
            topic_key=post.topic_key,
            target=target,
            post_text=post.text,
            now_utc=now_utc,
        )
        if row is None:
            return False
        log_id = int(row.id or 0)
    finally:
        db.close()

    if log_id <= 0 or target is None:
        return False

    try:
        client = telegram_bot.TelegramBotClient()
        _send_telegram_community_post(client, target, post)
        _update_telegram_post_log(
            log_id,
            log_model=models.TelegramDailyPostLog,
            status="sent",
            session_factory=session_maker,
        )
        logger.info(
            "telegram_auto_post_sent day=%s slot=%s topic=%s",
            day_key.isoformat(),
            due_slot_key,
            post.topic_key,
        )
        return True
    except Exception as ex:
        _update_telegram_post_log(
            log_id,
            log_model=models.TelegramDailyPostLog,
            status="failed",
            session_factory=session_maker,
            error=telegram_bot.sanitize_error(ex),
        )
        logger.exception("telegram_auto_post_failed")
        return False


def _run_telegram_instruction_post_once(
    *, session_factory=None, now_local: datetime | None = None
) -> bool:
    if (
        not telegram_bot.instruction_post_enabled()
        or not telegram_bot.telegram_enabled()
    ):
        return False

    current_local = _coerce_local_schedule_time(now_local)
    due_slot_key = _resolve_instruction_due_slot_key(current_local)
    if not due_slot_key:
        return False

    session_maker = session_factory or SessionLocal
    day_key = current_local.date()
    post = telegram_bot.build_instructional_post(day_key, due_slot_key)
    now_utc = _utc_now()
    log_id = 0
    target: _TelegramAutoPostTarget | None = None

    db = session_maker()
    try:
        target = _resolve_telegram_auto_post_target(db, post.topic_key)
        if target is None:
            return False
        row = _acquire_telegram_post_slot(
            db,
            log_model=models.TelegramInstructionPostLog,
            day_key=day_key,
            slot_key=due_slot_key,
            default_topic_key="comece_aqui",
            topic_key=post.topic_key,
            target=target,
            post_text=post.text,
            now_utc=now_utc,
        )
        if row is None:
            return False
        log_id = int(row.id or 0)
    finally:
        db.close()

    if log_id <= 0 or target is None:
        return False

    try:
        client = telegram_bot.TelegramBotClient()
        _send_telegram_community_post(client, target, post)
        _update_telegram_post_log(
            log_id,
            log_model=models.TelegramInstructionPostLog,
            status="sent",
            session_factory=session_maker,
        )
        logger.info(
            "telegram_instruction_post_sent day=%s slot=%s topic=%s",
            day_key.isoformat(),
            due_slot_key,
            post.topic_key,
        )
        return True
    except Exception as ex:
        _update_telegram_post_log(
            log_id,
            log_model=models.TelegramInstructionPostLog,
            status="failed",
            session_factory=session_maker,
            error=telegram_bot.sanitize_error(ex),
        )
        logger.exception("telegram_instruction_post_failed")
        return False


def _telegram_auto_post_loop(stop_event: threading.Event) -> None:
    while not stop_event.is_set():
        try:
            _run_telegram_daily_auto_post_once()
            _run_telegram_instruction_post_once()
        except Exception:
            logger.exception("telegram_auto_post_loop_failed")
        if stop_event.wait(telegram_bot.auto_post_poll_seconds()):
            break


def _start_telegram_auto_post_scheduler() -> None:
    if (
        not telegram_bot.auto_post_enabled()
        and not telegram_bot.instruction_post_enabled()
    ):
        return
    global _TELEGRAM_AUTO_POST_THREAD
    with _TELEGRAM_AUTO_POST_LOCK:
        if (
            _TELEGRAM_AUTO_POST_THREAD is not None
            and _TELEGRAM_AUTO_POST_THREAD.is_alive()
        ):
            return
        _TELEGRAM_AUTO_POST_STOP.clear()
        _TELEGRAM_AUTO_POST_THREAD = threading.Thread(
            target=_telegram_auto_post_loop,
            args=(_TELEGRAM_AUTO_POST_STOP,),
            name="telegram-auto-post",
            daemon=True,
        )
        _TELEGRAM_AUTO_POST_THREAD.start()


def _stop_telegram_auto_post_scheduler() -> None:
    global _TELEGRAM_AUTO_POST_THREAD
    with _TELEGRAM_AUTO_POST_LOCK:
        _TELEGRAM_AUTO_POST_STOP.set()
        if (
            _TELEGRAM_AUTO_POST_THREAD is not None
            and _TELEGRAM_AUTO_POST_THREAD.is_alive()
        ):
            _TELEGRAM_AUTO_POST_THREAD.join(timeout=1.5)
        _TELEGRAM_AUTO_POST_THREAD = None
