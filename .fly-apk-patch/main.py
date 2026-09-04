from contextlib import asynccontextmanager
from dataclasses import dataclass
from datetime import datetime, date, timezone, timedelta
import os
import json
import logging
import re
import threading
import time
from typing import Any
from fastapi import FastAPI, Depends, HTTPException, Header, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from sqlalchemy import text, and_, func, or_
from starlette.concurrency import run_in_threadpool
from .database import SessionLocal, engine, get_db
from . import emailer, models, schemas, services, mercadopago, telegram_bot
from .deps import authenticate_access_token
from .rate_limit import rate_limit
from .routers import auth as auth_router
from .routers import user as user_router
from .routers import quiz as quiz_router
from .routers import flashcard as flashcard_router


logger = logging.getLogger(__name__)
_BACKEND_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


@asynccontextmanager
async def _app_lifespan(_app: FastAPI):
    _start_telegram_auto_post_scheduler()
    try:
        yield
    finally:
        _stop_telegram_auto_post_scheduler()


app = FastAPI(title="Quiz Vance API", version="2.0.0", lifespan=_app_lifespan)

# ── CORS ──────────────────────────────────────────────────────────────────────
_CORS_ORIGINS = [
    o.strip()
    for o in os.getenv("CORS_ALLOWED_ORIGINS", "*").split(",")
    if o.strip()
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=_CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Routers novos (Flutter-compatible) ───────────────────────────────────────
app.include_router(auth_router.router)
app.include_router(user_router.router)
app.include_router(quiz_router.router)
app.include_router(flashcard_router.router)
APP_SECRET = str(os.getenv("APP_BACKEND_SECRET") or "").strip()
ALLOW_INSECURE_BOOT = str(os.getenv("ALLOW_INSECURE_BOOT") or "0").strip() == "1"
MP_WEBHOOK_TOKEN = str(os.getenv("MP_WEBHOOK_TOKEN") or "").strip()
LOGIN_WINDOW_SECONDS = max(60, int(os.getenv("LOGIN_WINDOW_SECONDS", "300") or 300))
LOGIN_FAIL_MAX = max(3, int(os.getenv("LOGIN_FAIL_MAX", "6") or 6))
_LOGIN_ATTEMPTS: dict[str, list[float]] = {}
_LOGIN_LOCK = threading.Lock()


def _run_login_cleanup() -> None:
    """Remove entradas de tentativas de login que já expiraram da janela."""
    while True:
        time.sleep(LOGIN_WINDOW_SECONDS * 2)
        cutoff = time.time() - LOGIN_WINDOW_SECONDS
        with _LOGIN_LOCK:
            stale = [k for k, ts in _LOGIN_ATTEMPTS.items() if not ts or ts[-1] < cutoff]
            for k in stale:
                del _LOGIN_ATTEMPTS[k]


_login_cleanup_thread = threading.Thread(
    target=_run_login_cleanup, daemon=True, name="login-attempts-cleanup"
)
_login_cleanup_thread.start()

# rate_limit é importado de .rate_limit (linha 19) — NÃO redefinir aqui.
_TELEGRAM_AUTO_POST_LOCK = threading.Lock()
_TELEGRAM_AUTO_POST_STOP = threading.Event()
_TELEGRAM_AUTO_POST_THREAD: threading.Thread | None = None

if not APP_SECRET and not ALLOW_INSECURE_BOOT:
    raise RuntimeError("APP_BACKEND_SECRET obrigatorio. Defina segredo forte (>=32 chars).")
if APP_SECRET and (len(APP_SECRET) < 32) and not ALLOW_INSECURE_BOOT:
    raise RuntimeError("APP_BACKEND_SECRET fraco. Use no minimo 32 caracteres.")
if mercadopago.enabled() and (not MP_WEBHOOK_TOKEN) and not ALLOW_INSECURE_BOOT:
    raise RuntimeError("MP_WEBHOOK_TOKEN obrigatorio quando Mercado Pago estiver habilitado.")


def _realign_users_id_sequence(db: Session | None = None) -> None:
    """Corrige sequencia de PK em Postgres quando houver insercoes com ID explicito."""
    stmt = text(
        "SELECT setval("
        "pg_get_serial_sequence('users', 'id'), "
        "COALESCE((SELECT MAX(id) FROM users), 0) + 1, "
        "false"
        ");"
    )
    try:
        if db is not None:
            bind = db.get_bind()
            dialect = str(getattr(getattr(bind, "dialect", None), "name", "") or "").lower()
            if "postgres" not in dialect:
                return
            db.execute(stmt)
            db.commit()
            return

        dialect = str(getattr(getattr(engine, "dialect", None), "name", "") or "").lower()
        if "postgres" not in dialect:
            return
        with engine.begin() as conn:
            conn.execute(stmt)
    except Exception:
        # Fallback silencioso: nao deve impedir o boot da API.
        if db is not None:
            db.rollback()


_realign_users_id_sequence()


def _ensure_payments_unique_index() -> None:
    stmt = text("CREATE UNIQUE INDEX IF NOT EXISTS uq_payments_provider_tx ON payments(provider, provider_tx_id)")
    try:
        with engine.begin() as conn:
            conn.execute(stmt)
    except Exception:
        # Nao bloqueia boot em base legada; tratar manualmente no runbook.
        pass


_ensure_payments_unique_index()


def _ensure_users_activity_columns() -> None:
    try:
        dialect = str(getattr(getattr(engine, "dialect", None), "name", "") or "").lower()
        with engine.begin() as conn:
            if "sqlite" in dialect:
                rows = conn.exec_driver_sql("PRAGMA table_info(users)").fetchall()
                cols = {str(row[1] or "").strip().lower() for row in rows}
                if "last_activity_day" not in cols:
                    conn.exec_driver_sql("ALTER TABLE users ADD COLUMN last_activity_day DATE")
            else:
                conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS last_activity_day DATE"))
            conn.execute(text("CREATE INDEX IF NOT EXISTS ix_users_last_activity_day ON users(last_activity_day)"))
    except Exception:
        # Nao bloqueia boot em base legada; corrigir manualmente apenas se necessario.
        pass


_ensure_users_activity_columns()


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


def _load_telegram_community_config(db: Session) -> models.TelegramCommunityConfig | None:
    return db.query(models.TelegramCommunityConfig).order_by(models.TelegramCommunityConfig.id.asc()).first()


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
    raw_thread_id = thread_map.get(str(topic_key or "").strip().lower()) or row.atualizacoes_thread_id
    try:
        thread_id = int(raw_thread_id or 0)
    except Exception:
        thread_id = 0
    if thread_id > 0:
        return thread_id
    return fallback_thread


def _extract_telegram_group_observation(update: dict[str, object] | None) -> tuple[int | str | None, int | None]:
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
        except Exception:
            thread_id = 0
        return chat_id, (thread_id if thread_id > 0 else None)
    return None, None


def _remember_telegram_group_target_from_update(db: Session, update: dict[str, object] | None) -> bool:
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
        except Exception:
            thread_id = 0
        if key and thread_id > 0:
            topic_map[key] = thread_id

    row = _load_telegram_community_config(db)
    if row is None:
        row = models.TelegramCommunityConfig(chat_id=telegram_bot.normalize_chat_id(chat_id))
        db.add(row)

    row.chat_id = telegram_bot.normalize_chat_id(chat_id)
    row.atualizacoes_thread_id = topic_map.get("atualizacoes") or row.atualizacoes_thread_id
    row.comece_aqui_thread_id = topic_map.get("comece_aqui") or row.comece_aqui_thread_id
    row.bate_papo_thread_id = topic_map.get("bate_papo") or row.bate_papo_thread_id
    row.resultados_thread_id = topic_map.get("resultados") or row.resultados_thread_id
    row.suporte_thread_id = topic_map.get("suporte") or row.suporte_thread_id
    row.feedbacks_thread_id = topic_map.get("feedbacks") or row.feedbacks_thread_id
    row.updated_at = _utc_now()
    db.commit()
    db.refresh(row)
    return row


def _resolve_telegram_auto_post_target(db: Session, topic_key: str) -> _TelegramAutoPostTarget | None:
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


def _find_telegram_post_row(db: Session, *, log_model, day_key: date, slot_key: str = "") -> Any | None:
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
    row = _find_telegram_post_row(db, log_model=log_model, day_key=day_key, slot_key=slot_key)
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
            row = _find_telegram_post_row(db, log_model=log_model, day_key=day_key, slot_key=slot_key)

    if row is None or row.sent_at is not None:
        return None

    last_attempt_at = row.last_attempt_at
    if isinstance(last_attempt_at, datetime) and last_attempt_at.tzinfo is None:
        last_attempt_at = last_attempt_at.replace(tzinfo=timezone.utc)
    if isinstance(last_attempt_at, datetime) and (now_utc - last_attempt_at) < retry_after:
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
            row.last_error = str(error or "")[:4000]
        db.commit()
    except Exception:
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


def _run_telegram_daily_auto_post_once(*, session_factory=None, now_local: datetime | None = None) -> bool:
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
            error=str(ex),
        )
        logger.exception("telegram_auto_post_failed")
        return False


def _run_telegram_instruction_post_once(*, session_factory=None, now_local: datetime | None = None) -> bool:
    if not telegram_bot.instruction_post_enabled() or not telegram_bot.telegram_enabled():
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
            error=str(ex),
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
    if not telegram_bot.auto_post_enabled() and not telegram_bot.instruction_post_enabled():
        return
    global _TELEGRAM_AUTO_POST_THREAD
    with _TELEGRAM_AUTO_POST_LOCK:
        if _TELEGRAM_AUTO_POST_THREAD is not None and _TELEGRAM_AUTO_POST_THREAD.is_alive():
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
        if _TELEGRAM_AUTO_POST_THREAD is not None and _TELEGRAM_AUTO_POST_THREAD.is_alive():
            _TELEGRAM_AUTO_POST_THREAD.join(timeout=1.5)
        _TELEGRAM_AUTO_POST_THREAD = None


def _backend_public_url(request: Request) -> str:
    env_url = str(os.getenv("BACKEND_PUBLIC_URL") or "").strip().rstrip("/")
    if env_url:
        return env_url
    return str(request.base_url).rstrip("/")


def _frontend_public_url() -> str:
    return str(os.getenv("FRONTEND_PUBLIC_URL") or "").strip().rstrip("/")


def _android_latest_version() -> str:
    return str(
        os.getenv("ANDROID_APP_LATEST_VERSION")
        or os.getenv("APP_LATEST_VERSION")
        or ""
    ).strip()


def _android_minimum_supported_version() -> str:
    return str(
        os.getenv("ANDROID_APP_MIN_SUPPORTED_VERSION")
        or os.getenv("APP_MIN_SUPPORTED_VERSION")
        or ""
    ).strip()


def _android_download_url() -> str:
    return str(telegram_bot.download_url() or "").strip()


def _android_release_file_path() -> str:
    return os.path.join(_BACKEND_ROOT, "releases", "android", "quiz-vance.apk")


def _android_versioned_release_file_path(version: str) -> str:
    version_clean = str(version or "").strip()
    if not re.fullmatch(r"[0-9A-Za-z._-]+", version_clean):
        return ""
    filename = f"quiz-vance-{version_clean}.apk"
    return os.path.join(_BACKEND_ROOT, "releases", "android", filename)


def _android_backend_download_url(request: Request | None = None) -> str:
    if not os.path.isfile(_android_release_file_path()):
        return ""
    base_url = ""
    if request is not None:
        try:
            base_url = str(request.base_url or "").strip().rstrip("/")
        except Exception:
            base_url = ""
    public_base = str(os.getenv("BACKEND_PUBLIC_URL") or "").strip().rstrip("/")
    root = public_base or base_url
    if not root:
        return ""
    return f"{root}/app/download/android/latest.apk"


def _android_release_notes() -> str:
    return str(
        os.getenv("ANDROID_APP_RELEASE_NOTES")
        or os.getenv("APP_RELEASE_NOTES")
        or ""
    ).strip()


def _android_published_at() -> datetime | None:
    raw = str(
        os.getenv("ANDROID_APP_PUBLISHED_AT")
        or os.getenv("APP_PUBLISHED_AT")
        or ""
    ).strip()
    if not raw:
        return None
    try:
        normalized = raw.replace("Z", "+00:00")
        return datetime.fromisoformat(normalized)
    except Exception:
        return None


def _version_parts(value: str) -> list[int]:
    parts = [int(chunk) for chunk in re.findall(r"\d+", str(value or ""))]
    return parts or [0]


def _is_version_newer(left: str, right: str) -> bool:
    left_parts = _version_parts(left)
    right_parts = _version_parts(right)
    size = max(len(left_parts), len(right_parts))
    left_parts.extend([0] * (size - len(left_parts)))
    right_parts.extend([0] * (size - len(right_parts)))
    return left_parts > right_parts


def _app_update_required_detail() -> str:
    minimum = _android_minimum_supported_version()
    latest = _android_latest_version()
    download = _android_download_url() or _android_backend_download_url()
    parts = ["Atualize o aplicativo para continuar."]
    if minimum:
        parts.append(f"Versao minima suportada: {minimum}.")
    if latest:
        parts.append(f"Versao disponivel: {latest}.")
    if download:
        parts.append(f"Baixe em: {download} (ou acesse o Telegram e baixe).")
    return " ".join(parts).strip()


def _require_supported_app_version(app_version: str | None) -> None:
    minimum = _android_minimum_supported_version()
    if not minimum:
        return
    current = str(app_version or "").strip()
    if not current:
        raise HTTPException(status_code=426, detail=_app_update_required_detail())
    if _is_version_newer(minimum, current):
        raise HTTPException(status_code=426, detail=_app_update_required_detail())


def _auth_out(db: Session, user: models.User, *, include_token: bool = False) -> schemas.AuthOut:
    plan = services.ensure_plan_row(db, user.id)
    active = services.premium_active(plan)
    out = schemas.AuthOut(
        user_id=user.id,
        name=user.name,
        login_id=str(getattr(user, "login_id", "") or ""),
        email_id=user.email_id,
        plan_code=plan.plan_code,
        premium_active=active,
        premium_until=plan.premium_until,
    )
    if include_token and APP_SECRET:
        out.access_token = services.create_access_token(
            APP_SECRET,
            user.id,
            user.email_id,
            services.current_auth_version(user),
        )
    return out


def _require_app_secret(app_secret: str | None) -> None:
    if not APP_SECRET:
        if ALLOW_INSECURE_BOOT:
            return
        raise HTTPException(status_code=503, detail="backend_misconfigured")
    if str(app_secret or "").strip() != APP_SECRET:
        raise HTTPException(status_code=403, detail="forbidden")


def _resolve_authenticated_user_id(
    requested_user_id: int,
    authorization: str | None,
    app_secret: str | None,
    db: Session,
    app_version: str | None = None,
) -> tuple[int, bool]:
    _require_supported_app_version(app_version)
    req_uid = int(requested_user_id or 0)
    if req_uid <= 0:
        raise HTTPException(status_code=400, detail="user_id_invalido")
    app_secret_value = str(app_secret or "").strip()
    if app_secret_value and APP_SECRET and app_secret_value == APP_SECRET:
        return req_uid, True

    if not APP_SECRET:
        if ALLOW_INSECURE_BOOT:
            return req_uid, True
        raise HTTPException(status_code=503, detail="backend_misconfigured")

    user, _payload = authenticate_access_token(authorization, db)
    token_uid = int(user.id or 0)
    if req_uid != token_uid:
        raise HTTPException(status_code=403, detail="token_user_mismatch")
    return token_uid, False


def _record_login_failure(key: str) -> int:
    now = time.time()
    with _LOGIN_LOCK:
        arr = [ts for ts in _LOGIN_ATTEMPTS.get(key, []) if (now - ts) <= LOGIN_WINDOW_SECONDS]
        arr.append(now)
        _LOGIN_ATTEMPTS[key] = arr
        return len(arr)


def _clear_login_failures(key: str) -> None:
    with _LOGIN_LOCK:
        _LOGIN_ATTEMPTS.pop(key, None)


def _clear_login_failures_for_identifier(identifier: str) -> None:
    prefix = f"{str(identifier or '').strip()}|"
    if not prefix:
        return
    with _LOGIN_LOCK:
        keys = [key for key in _LOGIN_ATTEMPTS.keys() if key.startswith(prefix)]
        for key in keys:
            _LOGIN_ATTEMPTS.pop(key, None)


def _is_login_blocked(key: str) -> bool:
    now = time.time()
    with _LOGIN_LOCK:
        arr = [ts for ts in _LOGIN_ATTEMPTS.get(key, []) if (now - ts) <= LOGIN_WINDOW_SECONDS]
        if arr:
            _LOGIN_ATTEMPTS[key] = arr
        else:
            _LOGIN_ATTEMPTS.pop(key, None)
        return len(arr) >= LOGIN_FAIL_MAX


def _resolve_register_login_id_payload(payload: schemas.RegisterIn) -> str:
    raw = str(payload.login_id or payload.id or "").strip()
    if not raw:
        raise HTTPException(status_code=422, detail="ID obrigatorio")
    try:
        return services.normalize_login_id(raw)
    except ValueError:
        raise HTTPException(
            status_code=422,
            detail="ID invalido. Use 3-40 caracteres com letras, numeros, ponto, underline ou hifen.",
        ) from None


def _resolve_register_email_payload(payload: schemas.RegisterIn) -> str:
    raw = str(payload.email_id or "").strip()
    if not raw:
        raise HTTPException(status_code=422, detail="E-mail obrigatorio")
    try:
        return services.normalize_email_id(raw)
    except ValueError:
        raise HTTPException(status_code=422, detail="E-mail invalido") from None


def _resolve_login_identifier_payload(payload: schemas.LoginIn) -> str:
    raw = str(payload.login_id or payload.id or payload.email_id or "").strip()
    if not raw:
        raise HTTPException(status_code=422, detail="ID obrigatorio")
    try:
        if "@" in raw:
            return services.normalize_email_id(raw)
        return services.normalize_login_id(raw)
    except ValueError:
        raise HTTPException(
            status_code=422,
            detail="ID invalido. Use 3-40 caracteres com letras, numeros, ponto, underline ou hifen.",
        ) from None


def _resolve_password_reset_identifier(raw_identifier: str) -> str:
    raw = str(raw_identifier or "").strip()
    if not raw:
        raise HTTPException(status_code=422, detail="Informe seu ID ou e-mail.")
    try:
        if "@" in raw:
            return services.normalize_email_id(raw)
        return services.normalize_login_id(raw)
    except ValueError:
        raise HTTPException(
            status_code=422,
            detail="Informe um ID ou e-mail valido.",
        ) from None


def _find_user_by_identifier(db: Session, identifier: str) -> models.User | None:
    normalized = _resolve_password_reset_identifier(identifier)
    return db.query(models.User).filter(
        or_(
            models.User.login_id == normalized,
            models.User.email_id == normalized,
        )
    ).first()


def _password_reset_ttl_minutes() -> int:
    return max(5, int(os.getenv("PASSWORD_RESET_TTL_MINUTES", "15") or 15))


def _fallback_login_id_for_user(user_id: int, email_id: str) -> str:
    email = str(email_id or "").strip().lower()
    if email:
        return email
    return f"user-{int(user_id)}"


def _mp_webhook_token_ok(request: Request) -> bool:
    if not MP_WEBHOOK_TOKEN:
        return True
    q_token = str(request.query_params.get("token") or "").strip()
    h_token = str(request.headers.get("X-Webhook-Token") or "").strip()
    return (q_token == MP_WEBHOOK_TOKEN) or (h_token == MP_WEBHOOK_TOKEN)


def _telegram_webhook_secret_ok(request: Request) -> bool:
    secret = str(telegram_bot.webhook_secret() or "").strip()
    if not secret:
        return True
    header_token = str(request.headers.get("X-Telegram-Bot-Api-Secret-Token") or "").strip()
    return header_token == secret


def _notify_telegram_checkout_event(
    title: str,
    *,
    user: models.User | None = None,
    checkout_id: str = "",
    plan_code: str = "",
    amount_cents: int = 0,
    provider: str = "",
    detail: str = "",
) -> None:
    if not telegram_bot.telegram_enabled():
        return
    try:
        telegram_bot.notify_admin_event(
            title,
            user_id=int(getattr(user, "id", 0) or 0),
            name=str(getattr(user, "name", "") or ""),
            email_id=str(getattr(user, "email_id", "") or ""),
            plan_code=str(plan_code or ""),
            amount_cents=int(amount_cents or 0),
            provider=str(provider or ""),
            checkout_id=str(checkout_id or ""),
            detail=str(detail or ""),
        )
    except Exception:
        # Alertas de Telegram nao podem derrubar fluxo de billing.
        pass


def _ensure_user_settings_row(db: Session, user_id: int) -> models.UserSettings:
    row = db.query(models.UserSettings).filter(models.UserSettings.user_id == int(user_id)).first()
    if row:
        return row
    row = models.UserSettings(
        user_id=int(user_id),
        provider="gemini",
        model="gemini-2.5-flash",
        economia_mode=0,
        telemetry_opt_in=0,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


def _user_settings_out(row: models.UserSettings, user_id: int) -> schemas.UserSettingsOut:
    active_key = (
        row.api_key_gemini if row.provider == "gemini"
        else row.api_key_openai if row.provider == "openai"
        else row.api_key_groq if row.provider == "groq"
        else row.api_key
    ) or row.api_key
    return schemas.UserSettingsOut(
        user_id=int(user_id),
        provider=str(row.provider or "gemini"),
        model=str(row.model or "gemini-2.5-flash"),
        api_key=None,
        api_key_gemini=None,
        api_key_openai=None,
        api_key_groq=None,
        has_api_key=bool(active_key),
        has_api_key_gemini=bool(row.api_key_gemini),
        has_api_key_openai=bool(row.api_key_openai),
        has_api_key_groq=bool(row.api_key_groq),
        economia_mode=bool(int(row.economia_mode or 0)),
        telemetry_opt_in=bool(int(row.telemetry_opt_in or 0)),
    )


@app.get("/health")
def health():
    return {"ok": True, "ts": datetime.now(timezone.utc).isoformat()}


@app.get("/health/ready")
def health_ready(db: Session = Depends(get_db)):
    try:
        db.execute(text("SELECT 1"))
        return {"ok": True, "db": "up", "ts": datetime.now(timezone.utc).isoformat()}
    except Exception as ex:
        raise HTTPException(status_code=503, detail="Banco de dados indisponível.") from ex


@app.get("/telegram/health")
def telegram_health(db: Session = Depends(get_db)):
    config = _load_telegram_community_config(db)
    stored_chat_id = str(getattr(config, "chat_id", "") or "").strip()
    updates_thread_id = _resolve_telegram_topic_thread_id(config, "atualizacoes")
    env_chat_id = telegram_bot.community_chat_id()
    return {
        "ok": True,
        "telegram_enabled": telegram_bot.telegram_enabled(),
        "webhook_secret_configured": bool(str(telegram_bot.webhook_secret() or "").strip()),
        "community_invite_configured": bool(telegram_bot.community_invite_url()),
        "download_url_configured": bool(telegram_bot.download_url()),
        "alert_chat_configured": bool(telegram_bot.alert_chat_id() is not None),
        "community_chat_configured": bool(stored_chat_id or env_chat_id is not None),
        "community_updates_thread_configured": bool(int(updates_thread_id or 0) > 0),
        "auto_post_enabled": telegram_bot.auto_post_enabled(),
        "auto_post_timezone": telegram_bot.auto_post_timezone_name(),
        "auto_post_hour": telegram_bot.auto_post_hour(),
        "auto_post_minute": telegram_bot.auto_post_minute(),
        "auto_post_times": telegram_bot.auto_post_times_labels(),
        "instruction_post_enabled": telegram_bot.instruction_post_enabled(),
        "instruction_post_hour": telegram_bot.instruction_post_hour(),
        "instruction_post_minute": telegram_bot.instruction_post_minute(),
        "instruction_post_times": telegram_bot.instruction_post_times_labels(),
        "auto_post_target_source": "database" if stored_chat_id else ("env" if env_chat_id is not None else "missing"),
    }


@app.api_route("/app/download/android/latest.apk", methods=["GET", "HEAD"])
def app_download_android_latest():
    apk_path = _android_release_file_path()
    if not os.path.isfile(apk_path):
        raise HTTPException(status_code=404, detail="apk_not_found")
    return FileResponse(
        path=apk_path,
        media_type="application/vnd.android.package-archive",
        filename="quiz-vance.apk",
        headers={"Cache-Control": "no-store"},
    )


@app.get("/app/download/android/{version}.apk")
def app_download_android_version(version: str):
    apk_path = _android_versioned_release_file_path(version)
    if not apk_path or not os.path.isfile(apk_path):
        raise HTTPException(status_code=404, detail="apk_not_found")
    return FileResponse(
        path=apk_path,
        media_type="application/vnd.android.package-archive",
        filename=f"quiz-vance-{version}.apk",
        headers={"Cache-Control": "no-store"},
    )


@app.get("/app/update", response_model=schemas.AppUpdateInfoOut)
def app_update_info(
    request: Request,
    platform: str = Query(default="android", alias="platform"),
):
    platform_clean = str(platform or "android").strip().lower() or "android"
    if platform_clean != "android":
        return schemas.AppUpdateInfoOut(ok=True, platform=platform_clean)
    download_url = _android_download_url() or _android_backend_download_url(request) or None
    return schemas.AppUpdateInfoOut(
        ok=True,
        platform="android",
        latest_version=_android_latest_version() or None,
        minimum_supported_version=_android_minimum_supported_version() or None,
        download_url=download_url,
        release_notes=_android_release_notes() or None,
        published_at=_android_published_at(),
    )


@app.post("/telegram/webhook")
async def telegram_webhook(request: Request, db: Session = Depends(get_db)):
    if not _telegram_webhook_secret_ok(request):
        raise HTTPException(status_code=403, detail="invalid_telegram_secret")
    try:
        payload = await request.json()
    except Exception:
        payload = {}
    if not isinstance(payload, dict):
        payload = {}
    try:
        _remember_telegram_group_target_from_update(db, payload)
    except Exception:
        db.rollback()
        logger.exception("telegram_group_target_observation_failed")
    result = await run_in_threadpool(telegram_bot.handle_update, payload)
    return {"ok": True, "result": result}


@app.post("/telegram/group/provision")
def telegram_group_provision(
    payload: schemas.TelegramProvisionIn,
    app_secret: str | None = Header(default=None, alias="X-App-Secret"),
    db: Session = Depends(get_db),
):
    _require_app_secret(app_secret)
    client = telegram_bot.TelegramBotClient()
    try:
        result = telegram_bot.provision_community_group(
            client,
            payload.chat_id,
            set_commands=bool(payload.set_commands),
            pin_messages=bool(payload.pin_messages),
            chat_title_override=str(payload.chat_title or ""),
            chat_description_override=str(payload.chat_description or ""),
            dry_run=bool(payload.dry_run),
        )
        if not bool(payload.dry_run):
            config = _persist_telegram_community_config(
                db,
                payload.chat_id,
                list(result.get("topics") or []),
            )
            result["auto_post_target_saved"] = True
            result["community_chat_id"] = str(config.chat_id or "")
            result["community_updates_thread_id"] = int(config.atualizacoes_thread_id or 0) or None
        return result
    except Exception as ex:
        raise HTTPException(status_code=400, detail=f"telegram_provision_failed: {ex}") from ex


@app.post("/telegram/webhook/configure")
def telegram_webhook_configure(
    payload: schemas.TelegramWebhookConfigIn,
    app_secret: str | None = Header(default=None, alias="X-App-Secret"),
):
    _require_app_secret(app_secret)
    client = telegram_bot.TelegramBotClient()
    try:
        return telegram_bot.configure_webhook(
            client,
            payload.public_base_url,
            drop_pending_updates=bool(payload.drop_pending_updates),
        )
    except Exception as ex:
        raise HTTPException(status_code=400, detail=f"telegram_webhook_config_failed: {ex}") from ex


@app.post("/auth/register", response_model=schemas.AuthOut)
def register(
    payload: schemas.RegisterIn,
    app_version: str | None = Header(default=None, alias="X-App-Version"),
    db: Session = Depends(get_db),
):
    _require_supported_app_version(app_version)
    login_id = _resolve_register_login_id_payload(payload)
    email_id = _resolve_register_email_payload(payload)
    name = str(payload.name or "").strip()
    if not name:
        raise HTTPException(status_code=422, detail="Nome obrigatorio")

    login_exists = db.query(models.User).filter(models.User.login_id == login_id).first()
    if login_exists:
        raise HTTPException(status_code=409, detail="ID ja cadastrado")
    email_exists = db.query(models.User).filter(models.User.email_id == email_id).first()
    if email_exists:
        raise HTTPException(status_code=409, detail="E-mail ja cadastrado")
    user = models.User(
        name=name,
        login_id=login_id,
        email_id=email_id,
        password_hash=services.hash_password(payload.password),
    )
    db.add(user)
    try:
        db.commit()
    except IntegrityError as ex:
        db.rollback()
        detail = str(getattr(ex, "orig", ex) or "").lower()
        if ("users_pkey" in detail) or ("duplicate key value violates unique constraint" in detail and "users" in detail):
            _realign_users_id_sequence(db)
            user = models.User(
                name=name,
                login_id=login_id,
                email_id=email_id,
                password_hash=services.hash_password(payload.password),
            )
            db.add(user)
            try:
                db.commit()
            except IntegrityError as ex2:
                db.rollback()
                detail2 = str(getattr(ex2, "orig", ex2) or "").lower()
                if ("login_id" in detail2) or ("users_login_id_key" in detail2) or ("ix_users_login_id" in detail2):
                    raise HTTPException(status_code=409, detail="ID ja cadastrado") from ex2
                if ("email_id" in detail2) or ("users_email_id_key" in detail2):
                    raise HTTPException(status_code=409, detail="E-mail ja cadastrado") from ex2
                raise HTTPException(status_code=500, detail="Falha ao criar usuario.") from ex2
        elif ("login_id" in detail) or ("users_login_id_key" in detail) or ("ix_users_login_id" in detail):
            raise HTTPException(status_code=409, detail="ID ja cadastrado") from ex
        elif ("email_id" in detail) or ("users_email_id_key" in detail):
            raise HTTPException(status_code=409, detail="E-mail ja cadastrado") from ex
        else:
            raise HTTPException(status_code=500, detail="Falha ao criar usuario.") from ex
    db.refresh(user)
    services.grant_initial_trial(db, user.id)
    return _auth_out(db, user, include_token=True)


@app.post("/auth/login", response_model=schemas.AuthOut)
def login(
    payload: schemas.LoginIn,
    request: Request,
    app_version: str | None = Header(default=None, alias="X-App-Version"),
    db: Session = Depends(get_db),
):
    _require_supported_app_version(app_version)
    identifier = _resolve_login_identifier_payload(payload)
    source = str(getattr(getattr(request, "client", None), "host", "") or "unknown")
    key = f"{identifier}|{source}"
    if _is_login_blocked(key):
        raise HTTPException(status_code=429, detail="Muitas tentativas de login. Aguarde alguns minutos.")

    user = db.query(models.User).filter(
        or_(
            models.User.login_id == identifier,
            models.User.email_id == identifier,
        )
    ).first()
    if not user:
        _record_login_failure(key)
        raise HTTPException(status_code=401, detail="Credenciais invalidas")
    if not services.verify_password(payload.password, user.password_hash):
        _record_login_failure(key)
        raise HTTPException(status_code=401, detail="Credenciais invalidas")
    if services.password_needs_rehash(user.password_hash):
        user.password_hash = services.hash_password(payload.password)
        db.commit()
        db.refresh(user)
    _clear_login_failures(key)
    return _auth_out(db, user, include_token=True)


@app.post("/auth/password-reset/request")
def request_password_reset(
    payload: schemas.PasswordResetRequestIn,
    app_version: str | None = Header(default=None, alias="X-App-Version"),
    db: Session = Depends(get_db),
):
    _require_supported_app_version(app_version)
    if not emailer.smtp_configured():
        raise HTTPException(
            status_code=503,
            detail="Recuperacao de senha indisponivel no momento. Servico de e-mail nao configurado.",
        )

    identifier = _resolve_password_reset_identifier(payload.identifier)
    user = _find_user_by_identifier(db, identifier)
    generic_response = {
        "ok": True,
        "message": "Se a conta existir, enviaremos um codigo para o e-mail cadastrado.",
    }
    if not user:
        return generic_response

    now = datetime.now(timezone.utc)
    ttl_minutes = _password_reset_ttl_minutes()
    active_rows = (
        db.query(models.PasswordResetToken)
        .filter(
            models.PasswordResetToken.user_id == user.id,
            models.PasswordResetToken.used_at.is_(None),
            models.PasswordResetToken.expires_at > now,
        )
        .all()
    )
    for row in active_rows:
        row.used_at = now

    code = services.generate_numeric_code(6)
    row = models.PasswordResetToken(
        user_id=user.id,
        code_hash=services.hash_password(code),
        expires_at=now + timedelta(minutes=ttl_minutes),
    )
    db.add(row)
    db.commit()
    db.refresh(row)

    try:
        emailer.send_password_reset_email(
            recipient_email=user.email_id,
            recipient_name=user.name,
            code=code,
            ttl_minutes=ttl_minutes,
        )
    except Exception as ex:
        row.used_at = datetime.now(timezone.utc)
        db.commit()
        logger.exception("password_reset_email_failed user_id=%s", user.id)
        raise HTTPException(
            status_code=502,
            detail=f"Falha ao enviar o e-mail de recuperacao: {ex}",
        ) from ex

    return generic_response


@app.post("/auth/password-reset/confirm")
def confirm_password_reset(
    payload: schemas.PasswordResetConfirmIn,
    app_version: str | None = Header(default=None, alias="X-App-Version"),
    db: Session = Depends(get_db),
):
    _require_supported_app_version(app_version)
    identifier = _resolve_password_reset_identifier(payload.identifier)
    code = str(payload.code or "").strip()
    if not code:
        raise HTTPException(status_code=422, detail="Informe o codigo recebido.")

    user = _find_user_by_identifier(db, identifier)
    if not user:
        raise HTTPException(status_code=400, detail="Codigo invalido ou expirado.")

    now = datetime.now(timezone.utc)
    active_rows = (
        db.query(models.PasswordResetToken)
        .filter(
            models.PasswordResetToken.user_id == user.id,
            models.PasswordResetToken.used_at.is_(None),
            models.PasswordResetToken.expires_at > now,
        )
        .order_by(models.PasswordResetToken.created_at.desc())
        .all()
    )

    matched_row = None
    for row in active_rows:
        if services.verify_password(code, row.code_hash):
            matched_row = row
            break
    if matched_row is None:
        raise HTTPException(status_code=400, detail="Codigo invalido ou expirado.")

    user.password_hash = services.hash_password(payload.new_password)
    services.revoke_user_sessions(db, user, commit=False)
    matched_row.used_at = now
    for row in active_rows:
        if row.id != matched_row.id:
            row.used_at = now
    _clear_login_failures_for_identifier(identifier)
    _clear_login_failures_for_identifier(user.email_id)
    _clear_login_failures_for_identifier(user.login_id)
    db.commit()

    return {"ok": True, "message": "Senha atualizada com sucesso."}


@app.get("/plans/me/{user_id}", response_model=schemas.AuthOut)
def my_plan(
    user_id: int,
    authorization: str | None = Header(default=None, alias="Authorization"),
    app_secret: str | None = Header(default=None, alias="X-App-Secret"),
    app_version: str | None = Header(default=None, alias="X-App-Version"),
    db: Session = Depends(get_db),
):
    uid, _internal = _resolve_authenticated_user_id(user_id, authorization, app_secret, db, app_version)
    user = db.query(models.User).filter(models.User.id == uid).first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuario nao encontrado")
    return _auth_out(db, user)


@app.post("/plans/activate")
def activate_plan(
    payload: schemas.ActivatePlanIn,
    app_secret: str | None = Header(default=None, alias="X-App-Secret"),
    db: Session = Depends(get_db),
):
    _require_app_secret(app_secret)
    # Ativacao direta bloqueada para evitar fraude por clique.
    raise HTTPException(status_code=403, detail="Ativacao direta bloqueada. Use checkout e confirmacao de pagamento.")


@app.post("/billing/checkout/start")
def start_checkout(
    payload: schemas.CheckoutStartIn,
    request: Request,
    authorization: str | None = Header(default=None, alias="Authorization"),
    app_secret: str | None = Header(default=None, alias="X-App-Secret"),
    app_version: str | None = Header(default=None, alias="X-App-Version"),
    db: Session = Depends(get_db),
):
    uid, internal_call = _resolve_authenticated_user_id(int(payload.user_id), authorization, app_secret, db, app_version)
    user = db.query(models.User).filter(models.User.id == uid).first()
    if not user:
        if not internal_call:
            raise HTTPException(status_code=404, detail="Usuario nao encontrado")
        email = str(payload.email_id or "").strip().lower()
        name = str(payload.name or "").strip()
        if not email:
            email = f"user-{int(uid)}@quizvance.local"
        if not name:
            name = f"Usuario {int(uid)}"
        user = models.User(
            id=int(uid),
            name=name,
            login_id=_fallback_login_id_for_user(int(uid), email),
            email_id=email,
            password_hash=services.hash_password(f"local-sync-{uid}"),
        )
        db.add(user)
        db.commit()
        db.refresh(user)
        services.ensure_plan_row(db, user.id)
    provider = str(payload.provider or "").strip().lower()
    if not provider:
        provider = "mercadopago" if mercadopago.enabled() else "manual"
    if provider in {"mercadopago", "mp"} and not mercadopago.enabled():
        raise HTTPException(status_code=400, detail="Mercado Pago nao configurado no backend.")

    checkout, msg = services.create_checkout_session(db, uid, payload.plan_code, provider)
    if not checkout:
        raise HTTPException(status_code=400, detail=msg)

    checkout_url = ""
    preference_id = ""
    if provider in {"mercadopago", "mp"}:
        backend_public = _backend_public_url(request)
        frontend_public = _frontend_public_url()
        notification_url = f"{backend_public}/billing/webhook/mercadopago"
        back_success = f"{frontend_public}/plans?checkout=success" if frontend_public else ""
        back_pending = f"{frontend_public}/plans?checkout=pending" if frontend_public else ""
        back_failure = f"{frontend_public}/plans?checkout=failure" if frontend_public else ""
        pref = mercadopago.create_checkout_preference(
            checkout_id=checkout.checkout_id,
            user_id=uid,
            plan_code=checkout.plan_code,
            amount_cents=int(checkout.amount_cents or 0),
            notification_url=notification_url,
            payer_email=user.email_id,
            back_url_success=back_success,
            back_url_pending=back_pending,
            back_url_failure=back_failure,
        )
        if mercadopago.is_test_token():
            checkout_url = str(pref.get("sandbox_init_point") or pref.get("init_point") or "").strip()
        else:
            checkout_url = str(pref.get("init_point") or pref.get("sandbox_init_point") or "").strip()
        preference_id = str(pref.get("id") or "").strip()
        if not checkout_url:
            reason = str(pref.get("message") or pref.get("error") or "").strip()
            if not reason:
                cause = pref.get("cause")
                if isinstance(cause, list) and cause:
                    first = cause[0] if isinstance(cause[0], dict) else {}
                    reason = str(first.get("description") or first.get("code") or "").strip()
            raise HTTPException(status_code=502, detail=f"Falha ao criar checkout no Mercado Pago. {reason}".strip())
        if preference_id:
            checkout.payment_code = preference_id
            db.commit()
            db.refresh(checkout)

    _notify_telegram_checkout_event(
        "Novo checkout iniciado",
        user=user,
        checkout_id=str(checkout.checkout_id or ""),
        plan_code=str(checkout.plan_code or ""),
        amount_cents=int(checkout.amount_cents or 0),
        provider=provider,
    )

    return {
        "ok": True,
        "message": msg,
        "checkout_id": checkout.checkout_id,
        "auth_token": checkout.auth_token,
        "payment_code": checkout.payment_code,
        "amount_cents": int(checkout.amount_cents or 0),
        "currency": checkout.currency,
        "plan_code": checkout.plan_code,
        "expires_at": checkout.expires_at,
        "provider": provider,
        "checkout_url": checkout_url,
        "preference_id": preference_id,
    }


@app.post("/billing/checkout/confirm")
def confirm_checkout(
    payload: schemas.CheckoutConfirmIn,
    authorization: str | None = Header(default=None, alias="Authorization"),
    app_secret: str | None = Header(default=None, alias="X-App-Secret"),
    app_version: str | None = Header(default=None, alias="X-App-Version"),
    db: Session = Depends(get_db),
):
    uid, _internal = _resolve_authenticated_user_id(int(payload.user_id), authorization, app_secret, db, app_version)
    user = db.query(models.User).filter(models.User.id == uid).first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuario nao encontrado")
    ok, msg, _row = services.confirm_checkout_session(
        db,
        uid,
        payload.checkout_id,
        payload.auth_token,
        payload.tx_id,
        payload.provider,
    )
    if not ok:
        raise HTTPException(status_code=400, detail=msg)
    _notify_telegram_checkout_event(
        "Pagamento confirmado manualmente",
        user=user,
        checkout_id=str(payload.checkout_id or ""),
        plan_code=str(getattr(_row, "plan_code", "") or ""),
        amount_cents=int(getattr(_row, "amount_cents", 0) or 0),
        provider=str(payload.provider or "manual"),
    )
    return {"ok": True, "message": msg, "plan": _auth_out(db, user)}


@app.post("/billing/checkout/reconcile")
def reconcile_checkout(
    payload: schemas.CheckoutReconcileIn,
    authorization: str | None = Header(default=None, alias="Authorization"),
    app_secret: str | None = Header(default=None, alias="X-App-Secret"),
    app_version: str | None = Header(default=None, alias="X-App-Version"),
    db: Session = Depends(get_db),
):
    uid, _internal = _resolve_authenticated_user_id(int(payload.user_id), authorization, app_secret, db, app_version)
    user = db.query(models.User).filter(models.User.id == uid).first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuario nao encontrado")
    checkout = (
        db.query(models.CheckoutSession)
        .filter(models.CheckoutSession.checkout_id == str(payload.checkout_id or "").strip())
        .first()
    )
    if not checkout:
        raise HTTPException(status_code=404, detail="Checkout nao encontrado")
    if int(checkout.user_id) != int(uid):
        raise HTTPException(status_code=403, detail="Checkout nao pertence ao usuario")

    if str(checkout.status or "") == "confirmed":
        return {"ok": True, "message": "Checkout ja confirmado.", "plan": _auth_out(db, user)}

    if str(checkout.provider or "").lower() not in {"mercadopago", "mp"}:
        raise HTTPException(status_code=400, detail="Reconciliacao automatica disponivel apenas para Mercado Pago.")

    payment = mercadopago.search_latest_payment_by_external_reference(str(checkout.checkout_id))
    if not payment:
        return {"ok": False, "message": "Pagamento ainda nao localizado no Mercado Pago.", "plan": _auth_out(db, user)}

    status = str(payment.get("status") or "").strip().lower()
    if status != "approved":
        return {"ok": False, "message": f"Pagamento ainda nao aprovado (status: {status or 'desconhecido'}).", "plan": _auth_out(db, user)}

    tx_id = str(payment.get("id") or "").strip()
    if not tx_id:
        return {"ok": False, "message": "Pagamento aprovado sem identificador de transacao.", "plan": _auth_out(db, user)}

    currency = str(payment.get("currency_id") or "BRL").strip() or "BRL"
    amount_cents = int(round(float(payment.get("transaction_amount") or 0) * 100))
    ok, msg, _payment_row = services.finalize_checkout_payment(
        db,
        checkout,
        provider="mercadopago",
        tx_id=tx_id,
        amount_cents=amount_cents,
        currency=currency,
        plan_code=str(checkout.plan_code or "premium_30"),
    )
    if not ok:
        raise HTTPException(status_code=400, detail=msg)
    _notify_telegram_checkout_event(
        "Pagamento reconciliado",
        user=user,
        checkout_id=str(checkout.checkout_id or ""),
        plan_code=str(checkout.plan_code or ""),
        amount_cents=int(amount_cents or 0),
        provider="mercadopago",
    )
    return {"ok": True, "message": msg, "plan": _auth_out(db, user)}


@app.post("/usage/consume")
def consume_usage(
    payload: schemas.ConsumeUsageIn,
    authorization: str | None = Header(default=None, alias="Authorization"),
    app_secret: str | None = Header(default=None, alias="X-App-Secret"),
    app_version: str | None = Header(default=None, alias="X-App-Version"),
    db: Session = Depends(get_db),
):
    uid, _internal = _resolve_authenticated_user_id(int(payload.user_id), authorization, app_secret, db, app_version)
    user = db.query(models.User).filter(models.User.id == uid).first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuario nao encontrado")
    ok, used = services.consume_daily_limit(db, uid, payload.feature_key, payload.limit_per_day)
    return {"allowed": ok, "used": used, "limit_per_day": payload.limit_per_day}


@app.post("/billing/webhook")
def billing_webhook(
    payload: schemas.WebhookPaymentIn,
    app_secret: str | None = Header(default=None, alias="X-App-Secret"),
    db: Session = Depends(get_db),
):
    _require_app_secret(app_secret)
    exists = db.query(models.WebhookEvent).filter(models.WebhookEvent.event_id == payload.event_id).first()
    if exists:
        return {"ok": True, "message": "evento ja processado"}

    event = models.WebhookEvent(
        provider=payload.provider,
        event_id=payload.event_id,
        payload_json=json.dumps(payload.model_dump(), ensure_ascii=False),
    )
    db.add(event)
    db.commit()

    payment = models.Payment(
        user_id=payload.user_id,
        provider=payload.provider,
        provider_tx_id=payload.tx_id,
        amount_cents=payload.amount_cents,
        currency=payload.currency,
        plan_code=payload.plan_code,
        status="paid" if payload.event_type == "payment_succeeded" else "pending",
        paid_at=datetime.now(timezone.utc) if payload.event_type == "payment_succeeded" else None,
    )
    db.add(payment)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        return {"ok": True, "message": "transacao ja registrada"}

    if payload.event_type == "payment_succeeded":
        services.activate_premium(db, payload.user_id, payload.plan_code)

    return {"ok": True}


@app.post("/billing/webhook/mercadopago")
async def billing_webhook_mercadopago(request: Request, db: Session = Depends(get_db)):
    if not _mp_webhook_token_ok(request):
        raise HTTPException(status_code=403, detail="invalid_webhook_token")
    try:
        payload = await request.json()
    except Exception:
        payload = {}
    if not isinstance(payload, dict):
        payload = {}
    params = request.query_params
    topic = str(payload.get("type") or payload.get("topic") or params.get("type") or params.get("topic") or "").strip().lower()
    action = str(payload.get("action") or params.get("action") or "").strip().lower()

    data = payload.get("data") if isinstance(payload.get("data"), dict) else {}
    payment_id = str(data.get("id") or params.get("data.id") or "").strip()
    if not payment_id:
        # Alguns formatos antigos mandam id diretamente na query.
        qid = str(params.get("id") or "").strip()
        if qid.isdigit():
            payment_id = qid

    if "payment" not in topic and "payment" not in action:
        return {"ok": True, "message": "evento ignorado"}
    if not payment_id:
        return {"ok": True, "message": "evento sem payment_id"}

    event_id = f"mp:{payment_id}:{action or topic or 'event'}"
    exists = db.query(models.WebhookEvent).filter(models.WebhookEvent.event_id == event_id).first()
    if exists:
        return {"ok": True, "message": "evento ja processado"}

    payment = await run_in_threadpool(mercadopago.get_payment, payment_id)
    status = str(payment.get("status") or "").strip().lower()
    metadata = payment.get("metadata") if isinstance(payment.get("metadata"), dict) else {}
    checkout_id = str(metadata.get("checkout_id") or payment.get("external_reference") or "").strip()
    tx_id = str(payment.get("id") or payment_id).strip()
    plan_code = str(metadata.get("plan_code") or "").strip().lower()
    currency = str(payment.get("currency_id") or "BRL").strip() or "BRL"
    amount_cents = int(round(float(payment.get("transaction_amount") or 0) * 100))

    event_payload = {
        "notification": payload,
        "query": dict(params),
        "payment": payment,
    }
    event = models.WebhookEvent(
        provider="mercadopago",
        event_id=event_id,
        payload_json=json.dumps(event_payload, ensure_ascii=False),
    )
    db.add(event)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        return {"ok": True, "message": "evento ja processado"}

    if status != "approved":
        db.commit()
        return {"ok": True, "message": f"status {status or 'unknown'} ignorado"}
    if not checkout_id:
        db.commit()
        return {"ok": True, "message": "pagamento aprovado sem checkout_id"}

    checkout = db.query(models.CheckoutSession).filter(models.CheckoutSession.checkout_id == checkout_id).first()
    if not checkout:
        db.commit()
        return {"ok": True, "message": "checkout nao encontrado"}
    external_reference = str(payment.get("external_reference") or "").strip()
    if external_reference and external_reference != str(checkout.checkout_id):
        db.commit()
        return {"ok": True, "message": "external_reference divergente"}

    ok, msg, _payment_row = services.finalize_checkout_payment(
        db,
        checkout,
        provider="mercadopago",
        tx_id=tx_id,
        amount_cents=amount_cents,
        currency=currency,
        plan_code=plan_code or str(checkout.plan_code or "premium_30"),
    )
    if not ok:
        raise HTTPException(status_code=400, detail=msg)
    user = db.query(models.User).filter(models.User.id == int(checkout.user_id)).first()
    _notify_telegram_checkout_event(
        "Pagamento aprovado no Mercado Pago",
        user=user,
        checkout_id=str(checkout.checkout_id or ""),
        plan_code=str(checkout.plan_code or ""),
        amount_cents=int(amount_cents or 0),
        provider="mercadopago",
        detail=f"payment_id={tx_id}",
    )
    return {"ok": True, "message": msg}


@app.post("/internal/upsert-user")
def upsert_user(
    payload: schemas.UpsertUserIn,
    app_secret: str | None = Header(default=None, alias="X-App-Secret"),
    db: Session = Depends(get_db),
):
    _require_app_secret(app_secret)

    user = db.query(models.User).filter(models.User.id == payload.user_id).first()
    if user:
        user.name = payload.name.strip()
        user.email_id = payload.email_id.strip().lower()
        user.login_id = (
            services.normalize_login_id(payload.login_id)
            if str(payload.login_id or "").strip()
            else _fallback_login_id_for_user(payload.user_id, payload.email_id)
        )
        db.commit()
        db.refresh(user)
        services.ensure_plan_row(db, user.id)
        return {"ok": True, "user_id": user.id, "updated": True}

    # Insercao com id fixo para mapear com app local
    user = models.User(
        id=payload.user_id,
        name=payload.name.strip(),
        login_id=(
            services.normalize_login_id(payload.login_id)
            if str(payload.login_id or "").strip()
            else _fallback_login_id_for_user(payload.user_id, payload.email_id)
        ),
        email_id=payload.email_id.strip().lower(),
        password_hash=services.hash_password(f"local-sync-{payload.user_id}"),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    services.ensure_plan_row(db, user.id)
    return {"ok": True, "user_id": user.id, "created": True}


@app.post("/internal/stats/quiz/batch")
def sync_quiz_stats_batch(
    payload: schemas.QuizStatsBatchIn,
    authorization: str | None = Header(default=None, alias="Authorization"),
    app_secret: str | None = Header(default=None, alias="X-App-Secret"),
    app_version: str | None = Header(default=None, alias="X-App-Version"),
    db: Session = Depends(get_db),
):
    uid, _internal = _resolve_authenticated_user_id(int(payload.user_id), authorization, app_secret, db, app_version)
    user = db.query(models.User).filter(models.User.id == int(uid)).first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuario nao encontrado")

    processed = 0
    duplicated = 0
    total_xp = 0
    consumed_event_ids: list[str] = []
    activity_days: set[date] = set()
    now = datetime.now(timezone.utc)
    events = list(payload.events or [])[:1000]

    for event in events:
        event_id = str(getattr(event, "event_id", "") or "").strip()[:120]
        if not event_id:
            continue

        exists = (
            db.query(models.QuizStatsEvent)
            .filter(
                models.QuizStatsEvent.user_id == int(uid),
                models.QuizStatsEvent.event_id == event_id,
            )
            .first()
        )
        if exists:
            duplicated += 1
            consumed_event_ids.append(event_id)
            continue

        questoes_delta = max(0, int(getattr(event, "questoes_delta", 0) or 0))
        acertos_delta = max(0, int(getattr(event, "acertos_delta", 0) or 0))
        xp_delta = max(0, int(getattr(event, "xp_delta", 0) or 0))
        correta = bool(getattr(event, "correta", False))
        if acertos_delta == 0 and correta:
            acertos_delta = 1
        if questoes_delta == 0:
            questoes_delta = 1
        if acertos_delta > questoes_delta:
            acertos_delta = questoes_delta

        occurred_at = getattr(event, "occurred_at", None)
        if not isinstance(occurred_at, datetime):
            occurred_at = now
        day_key = occurred_at.date() if isinstance(occurred_at.date(), date) else now.date()

        daily = (
            db.query(models.QuizStatsDaily)
            .filter(
                models.QuizStatsDaily.user_id == int(uid),
                models.QuizStatsDaily.day_key == day_key,
            )
            .first()
        )
        if not daily:
            daily = models.QuizStatsDaily(user_id=int(uid), day_key=day_key, questoes=0, acertos=0, xp_ganho=0)
            db.add(daily)

        daily.questoes = int(daily.questoes or 0) + questoes_delta
        daily.acertos = int(daily.acertos or 0) + acertos_delta
        daily.xp_ganho = int(daily.xp_ganho or 0) + xp_delta
        daily.updated_at = now
        activity_days.add(day_key)

        db.add(
            models.QuizStatsEvent(
                user_id=int(uid),
                event_id=event_id,
                occurred_at=occurred_at,
                questoes_delta=questoes_delta,
                acertos_delta=acertos_delta,
                xp_delta=xp_delta,
                correta=1 if correta else 0,
            )
        )
        processed += 1
        total_xp += xp_delta
        consumed_event_ids.append(event_id)

    if processed > 0:
        user.xp = int(user.xp or 0) + int(total_xp)
        for day_key in sorted(activity_days):
            services.apply_user_daily_activity(user, day_key)
    db.commit()

    return {
        "ok": True,
        "processed": int(processed),
        "duplicated": int(duplicated),
        "received": int(len(events)),
        "consumed_event_ids": consumed_event_ids,
    }


@app.post("/internal/stats/activity/ping")
def ping_daily_activity(
    payload: schemas.QuizActivityPingIn,
    authorization: str | None = Header(default=None, alias="Authorization"),
    app_secret: str | None = Header(default=None, alias="X-App-Secret"),
    app_version: str | None = Header(default=None, alias="X-App-Version"),
    db: Session = Depends(get_db),
):
    uid, _internal = _resolve_authenticated_user_id(int(payload.user_id), authorization, app_secret, db, app_version)
    user = db.query(models.User).filter(models.User.id == int(uid)).first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuario nao encontrado")
    if isinstance(payload.activity_day, date):
        activity_day = payload.activity_day
    else:
        try:
            tz_offset = max(-14.0, min(14.0, float(payload.tz_offset_hours or 0.0)))
            client_tz = timezone(timedelta(hours=tz_offset))
            activity_day = datetime.now(client_tz).date()
        except Exception:
            activity_day = date.today()
    streak_dias, last_activity_day = services.merge_user_daily_activity(
        db,
        int(uid),
        activity_day,
        int(payload.streak_dias or 0) if payload.streak_dias is not None else None,
    )
    return {
        "ok": True,
        "user_id": int(uid),
        "streak_dias": int(streak_dias or 0),
        "last_activity_day": last_activity_day.isoformat() if isinstance(last_activity_day, date) else None,
    }


@app.get("/internal/stats/quiz/summary/{user_id}", response_model=schemas.QuizStatsSummaryOut)
def get_quiz_stats_summary(
    user_id: int,
    tz_offset_hours: float = Query(default=0.0, alias="tz_offset_hours"),
    authorization: str | None = Header(default=None, alias="Authorization"),
    app_secret: str | None = Header(default=None, alias="X-App-Secret"),
    app_version: str | None = Header(default=None, alias="X-App-Version"),
    db: Session = Depends(get_db),
):
    uid, _internal = _resolve_authenticated_user_id(int(user_id), authorization, app_secret, db, app_version)
    user = db.query(models.User).filter(models.User.id == int(uid)).first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuario nao encontrado")
    rows = db.query(models.QuizStatsDaily).filter(models.QuizStatsDaily.user_id == int(uid)).all()
    total_questoes = sum(int(r.questoes or 0) for r in rows)
    total_acertos = sum(int(r.acertos or 0) for r in rows)
    total_xp = int(user.xp or 0)
    # Calcular today no timezone do cliente (tz_offset_hours pode ser negativo ex: -3 para Brasilia)
    try:
        tz_offset = max(-14.0, min(14.0, float(tz_offset_hours or 0)))
        client_tz = timezone(timedelta(hours=tz_offset))
        today_key = datetime.now(client_tz).date()
    except Exception:
        today_key = date.today()
    today_row = (
        db.query(models.QuizStatsDaily)
        .filter(
            models.QuizStatsDaily.user_id == int(uid),
            models.QuizStatsDaily.day_key == today_key,
        )
        .first()
    )
    today_questoes = int((today_row.questoes if today_row else 0) or 0)
    today_acertos = int((today_row.acertos if today_row else 0) or 0)
    today_xp = int((today_row.xp_ganho if today_row else 0) or 0)
    daily_map: dict[date, tuple[int, int]] = {}
    for row in rows:
        try:
            key = row.day_key
            if not isinstance(key, date):
                continue
            daily_map[key] = (
                max(0, int(row.questoes or 0)),
                max(0, int(row.acertos or 0)),
            )
        except Exception:
            continue
    last_activity_day = user.last_activity_day if isinstance(user.last_activity_day, date) else None
    try:
        daily_activity_days = [k for k, v in daily_map.items() if isinstance(k, date) and int((v or (0, 0))[0] or 0) > 0]
        derived_last_activity_day = max(daily_activity_days) if daily_activity_days else None
    except Exception:
        daily_activity_days = []
        derived_last_activity_day = None
    if derived_last_activity_day and (last_activity_day is None or derived_last_activity_day > last_activity_day):
        last_activity_day = derived_last_activity_day

    def _contiguous_streak_from(start_day: date | None) -> int:
        if not isinstance(start_day, date):
            return 0
        count = 0
        cursor_day = start_day
        while True:
            stats = daily_map.get(cursor_day)
            if not stats or int((stats or (0, 0))[0] or 0) <= 0:
                break
            count += 1
            cursor_day = cursor_day - timedelta(days=1)
        return count

    streak_base = max(0, int(user.streak_days or 0))
    contiguous_hint = _contiguous_streak_from(last_activity_day)
    if contiguous_hint > 0:
        streak_base = max(streak_base, contiguous_hint)

    if isinstance(last_activity_day, date):
        gap_days = int((today_key - last_activity_day).days)
        # Mantem streak durante o dia seguinte sem atividade;
        # apos mais de um dia completo sem estudar, zera.
        streak_dias = streak_base if gap_days <= 1 else 0
    else:
        streak_dias = 0
    return schemas.QuizStatsSummaryOut(
        user_id=int(uid),
        total_questoes=max(0, int(total_questoes)),
        total_acertos=max(0, int(total_acertos)),
        total_xp=max(0, int(total_xp)),
        today_questoes=max(0, today_questoes),
        today_acertos=max(0, today_acertos),
        today_xp=max(0, today_xp),
        streak_dias=max(0, int(streak_dias)),
        last_activity_day=last_activity_day,
    )


@app.get("/internal/stats/quiz/leaderboard/{user_id}", response_model=schemas.LeaderboardOut)
def get_quiz_stats_leaderboard(
    user_id: int,
    period: str = Query(default="Geral", alias="period"),
    limit: int = Query(default=50, ge=1, le=100),
    authorization: str | None = Header(default=None, alias="Authorization"),
    app_secret: str | None = Header(default=None, alias="X-App-Secret"),
    app_version: str | None = Header(default=None, alias="X-App-Version"),
    db: Session = Depends(get_db),
):
    uid, _internal = _resolve_authenticated_user_id(int(user_id), authorization, app_secret, db, app_version)
    user = db.query(models.User).filter(models.User.id == int(uid)).first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuario nao encontrado")

    period_clean = "Hoje" if str(period or "").strip().lower() == "hoje" else "Geral"
    today_key = date.today()

    stats_query = (
        db.query(
            models.QuizStatsDaily.user_id.label("user_id"),
            func.coalesce(func.sum(models.QuizStatsDaily.questoes), 0).label("total_questoes"),
            func.coalesce(func.sum(models.QuizStatsDaily.acertos), 0).label("total_acertos"),
        )
    )
    if period_clean == "Hoje":
        stats_query = stats_query.filter(models.QuizStatsDaily.day_key == today_key)
    stats_subquery = stats_query.group_by(models.QuizStatsDaily.user_id).subquery()

    users_query = (
        db.query(
            models.User.id.label("user_id"),
            models.User.name.label("name"),
            models.User.xp.label("xp"),
            models.User.last_activity_day.label("last_activity_day"),
            func.coalesce(stats_subquery.c.total_questoes, 0).label("total_questoes"),
            func.coalesce(stats_subquery.c.total_acertos, 0).label("total_acertos"),
        )
        .outerjoin(stats_subquery, stats_subquery.c.user_id == models.User.id)
    )
    if period_clean == "Hoje":
        users_query = users_query.filter(models.User.last_activity_day == today_key)

    total_participantes = int(users_query.count() or 0)
    rows = (
        users_query
        .order_by(models.User.xp.desc(), models.User.id.asc())
        .limit(int(limit))
        .all()
    )

    my_position: int | None = None
    if period_clean != "Hoje" or user.last_activity_day == today_key:
        higher_count = (
            db.query(func.count(models.User.id))
            .filter(
                or_(
                    models.User.xp > int(user.xp or 0),
                    and_(models.User.xp == int(user.xp or 0), models.User.id < int(uid)),
                )
            )
        )
        if period_clean == "Hoje":
            higher_count = higher_count.filter(models.User.last_activity_day == today_key)
        my_position = int(higher_count.scalar() or 0) + 1

    out_rows: list[schemas.LeaderboardEntryOut] = []
    for row in rows:
        total_questoes = max(0, int(getattr(row, "total_questoes", 0) or 0))
        total_acertos = max(0, int(getattr(row, "total_acertos", 0) or 0))
        taxa_acerto = (total_acertos / total_questoes * 100.0) if total_questoes > 0 else 0.0
        out_rows.append(
            schemas.LeaderboardEntryOut(
                user_id=int(getattr(row, "user_id", 0) or 0),
                name=str(getattr(row, "name", "") or ""),
                xp=max(0, int(getattr(row, "xp", 0) or 0)),
                total_questoes=total_questoes,
                total_acertos=total_acertos,
                taxa_acerto=round(taxa_acerto, 2),
                last_activity_day=getattr(row, "last_activity_day", None),
            )
        )

    return schemas.LeaderboardOut(
        period=period_clean,
        total_participantes=total_participantes,
        top_xp=max(0, int((getattr(rows[0], "xp", 0) if rows else 0) or 0)),
        my_position=my_position,
        rows=out_rows,
    )


@app.get("/internal/user-settings/{user_id}", response_model=schemas.UserSettingsOut)
def get_user_settings(
    user_id: int,
    authorization: str | None = Header(default=None, alias="Authorization"),
    app_secret: str | None = Header(default=None, alias="X-App-Secret"),
    app_version: str | None = Header(default=None, alias="X-App-Version"),
    db: Session = Depends(get_db),
):
    uid, _internal = _resolve_authenticated_user_id(int(user_id), authorization, app_secret, db, app_version)
    user = db.query(models.User).filter(models.User.id == int(uid)).first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuario nao encontrado")
    row = _ensure_user_settings_row(db, int(uid))
    return _user_settings_out(row, int(uid))


@app.post("/internal/user-settings", response_model=schemas.UserSettingsOut)
def upsert_user_settings(
    payload: schemas.UpsertUserSettingsIn,
    authorization: str | None = Header(default=None, alias="Authorization"),
    app_secret: str | None = Header(default=None, alias="X-App-Secret"),
    app_version: str | None = Header(default=None, alias="X-App-Version"),
    db: Session = Depends(get_db),
):
    uid, _internal = _resolve_authenticated_user_id(int(payload.user_id), authorization, app_secret, db, app_version)
    user = db.query(models.User).filter(models.User.id == int(uid)).first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuario nao encontrado")
    if not APP_SECRET:
        raise HTTPException(status_code=503, detail="backend_misconfigured")

    row = _ensure_user_settings_row(db, int(uid))
    row.provider = str(payload.provider or "gemini").strip().lower() or "gemini"
    row.model = str(payload.model or "gemini-2.5-flash").strip() or "gemini-2.5-flash"
    if payload.api_key is not None:
        row.api_key = services.encrypt_api_key(APP_SECRET, payload.api_key)
    if payload.api_key_gemini is not None:
        row.api_key_gemini = services.encrypt_api_key(APP_SECRET, payload.api_key_gemini)
    if payload.api_key_openai is not None:
        row.api_key_openai = services.encrypt_api_key(APP_SECRET, payload.api_key_openai)
    if payload.api_key_groq is not None:
        row.api_key_groq = services.encrypt_api_key(APP_SECRET, payload.api_key_groq)
    row.economia_mode = 1 if bool(payload.economia_mode) else 0
    row.telemetry_opt_in = 1 if bool(payload.telemetry_opt_in) else 0
    row.updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(row)
    return _user_settings_out(row, int(uid))
