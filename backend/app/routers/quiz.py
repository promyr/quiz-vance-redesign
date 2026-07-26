"""
routers/quiz.py — Geração e submissão de quizzes, simulados, quiz aberto,
                  plano de estudos, biblioteca e ranking.
"""

from __future__ import annotations

import hashlib
import logging
import re
import uuid
from datetime import date, datetime, timedelta, timezone

import httpx
from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import func, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .. import ai_service as ai
from .. import models, services
from ..ai_gateway import build_ai_candidates, call_ai_with_fallback
from ..ai_provider_config import normalize_provider
from ..database import get_db
from ..deps import require_user as _require_user
from ..rate_limit import rate_limit

# ── Premium plan constants ────────────────────────────────────────────────────

_FREE_QUIZ_DAILY_LIMIT = 5  # gerações de quiz por dia para free
_FREE_SIMULADO_WEEKLY_LIMIT = 1  # simulados por semana para free
_FREE_OPEN_QUIZ_WEEKLY_LIMIT = 1  # quiz dissertativo por semana para free

logger = logging.getLogger(__name__)

router = APIRouter(tags=["quiz"])


# ── AI helper — pega configurações do usuário ─────────────────────────────────


def _call_ai_for_user(
    user: models.User,
    db: Session,
    *,
    requested_provider: str | None = None,
    system_prompt: str,
    user_prompt: str,
) -> tuple[str, str]:
    candidates = build_ai_candidates(
        user,
        db,
        requested_provider=requested_provider,
    )
    if not candidates:
        raise HTTPException(
            status_code=503,
            detail="Nenhuma chave de IA ativa no servidor. Avise o administrador.",
        )
    text, selected = call_ai_with_fallback(
        db,
        candidates,
        system_prompt=system_prompt,
        user_prompt=user_prompt,
    )
    return text, selected.provider


def _extract_provider_error_message(exc: Exception) -> str | None:
    if not isinstance(exc, httpx.HTTPStatusError):
        return None

    response = exc.response
    try:
        payload = response.json()
    except Exception:
        payload = None

    candidates: list[str] = []
    if isinstance(payload, dict):
        error = payload.get("error")
        if isinstance(error, dict):
            for key in ("message", "detail", "code", "type"):
                value = error.get(key)
                if isinstance(value, str):
                    candidates.append(value)
        for key in ("detail", "message", "error"):
            value = payload.get(key)
            if isinstance(value, str):
                candidates.append(value)

    text = response.text.strip()
    if text:
        candidates.append(text)

    for candidate in candidates:
        cleaned = re.sub(r"\s+", " ", candidate).strip()
        if cleaned:
            return cleaned[:240]
    return None


def _raise_ai_provider_failure(action: str, provider: str, exc: Exception) -> None:
    provider_label = provider.upper()

    if isinstance(exc, httpx.HTTPStatusError):
        status = exc.response.status_code
        provider_detail = _extract_provider_error_message(exc)

        if status in (401, 403):
            detail = (
                f"Falha de autenticacao no provedor {provider_label}. "
                "Verifique a chave de API salva para esse provedor."
            )
            if provider_detail:
                detail = f"{detail} Detalhe: {provider_detail}"
            raise HTTPException(status_code=502, detail=detail)

        if status == 429:
            detail = (
                f"O provedor {provider_label} recusou a geracao por limite, credito "
                "ou rate limit. Tente novamente ou use outro provedor."
            )
            if provider_detail:
                detail = f"{detail} Detalhe: {provider_detail}"
            raise HTTPException(status_code=502, detail=detail)

        detail = f"Erro no provedor {provider_label} ao {action}."
        if provider_detail:
            detail = f"{detail} Detalhe: {provider_detail}"
        raise HTTPException(status_code=502, detail=detail)

    raise HTTPException(
        status_code=502,
        detail=f"Erro ao {action} com IA usando {provider_label}. Tente novamente.",
    )


# ── Premium helpers ───────────────────────────────────────────────────────────


def _is_premium(user: models.User, db: Session) -> bool:
    """True se o usuário tem um plano premium ou trial ativo."""
    plan = db.query(models.UserPlan).filter(models.UserPlan.user_id == user.id).first()
    if not plan:
        return False
    if plan.plan_code in ("premium_30", "premium", "trial"):
        if plan.premium_until is None:
            return True  # sem expiração = vitalício
        return plan.premium_until.replace(tzinfo=timezone.utc) > datetime.now(
            timezone.utc
        )
    return False


def _get_usage_today(db: Session, user_id: int, feature_key: str) -> models.UsageDaily:
    """Retorna ou cria o registro de uso do dia para user+feature_key."""
    today = datetime.now(timezone.utc).date()
    row = (
        db.query(models.UsageDaily)
        .filter(
            models.UsageDaily.user_id == user_id,
            models.UsageDaily.feature_key == feature_key,
            models.UsageDaily.day_key == today,
        )
        .first()
    )
    if not row:
        row = models.UsageDaily(
            user_id=user_id,
            feature_key=feature_key,
            day_key=today,
            used_count=0,
        )
        db.add(row)
        db.flush()
    return row


def _check_quiz_limit(user: models.User, db: Session) -> None:
    """Lança HTTP 429 se usuário free atingiu o limite diário de geração de quizzes."""
    if _is_premium(user, db):
        return
    row = _get_usage_today(db, user.id, "quiz_generate")
    if int(row.used_count or 0) >= _FREE_QUIZ_DAILY_LIMIT:
        raise HTTPException(
            status_code=429,
            detail=(
                f"Você já gerou {_FREE_QUIZ_DAILY_LIMIT} quizzes hoje. "
                "Faça upgrade para Premium e tenha quizzes ilimitados."
            ),
        )


def _check_simulado_limit(user: models.User, db: Session) -> None:
    """Lança HTTP 429 se usuário free atingiu o limite semanal de simulados."""
    if _is_premium(user, db):
        return
    used_this_week = _get_usage_this_week(db, user.id, "simulado_generate")
    if used_this_week >= _FREE_SIMULADO_WEEKLY_LIMIT:
        raise HTTPException(
            status_code=429,
            detail=(
                f"Você já fez {_FREE_SIMULADO_WEEKLY_LIMIT} simulado esta semana. "
                "Faça upgrade para Premium e tenha simulados ilimitados."
            ),
        )


def _get_week_start(today: date | None = None) -> date:
    reference = today or datetime.now(timezone.utc).date()
    return reference - timedelta(days=reference.weekday())


def _get_usage_this_week(db: Session, user_id: int, feature_key: str) -> int:
    today = datetime.now(timezone.utc).date()
    week_start = _get_week_start(today)
    total = (
        db.query(func.coalesce(func.sum(models.UsageDaily.used_count), 0))
        .filter(
            models.UsageDaily.user_id == user_id,
            models.UsageDaily.feature_key == feature_key,
            models.UsageDaily.day_key >= week_start,
            models.UsageDaily.day_key <= today,
        )
        .scalar()
    )
    return int(total or 0)


def _check_open_quiz_limit(user: models.User, db: Session) -> None:
    """Lança HTTP 429 se usuário free atingiu o limite semanal do dissertativo."""
    if _is_premium(user, db):
        return

    used_this_week = _get_usage_this_week(db, user.id, "open_quiz_generate")
    if used_this_week >= _FREE_OPEN_QUIZ_WEEKLY_LIMIT:
        raise HTTPException(
            status_code=429,
            detail=(
                "Usuários free podem gerar 1 questão dissertativa por semana. "
                "Faça upgrade para Premium e libere o modo dissertativo ilimitado."
            ),
        )


def _increment_usage(db: Session, user_id: int, feature_key: str) -> None:
    """Incrementa o contador de uso do dia. Falhas silenciosas não bloqueiam o fluxo."""
    try:
        services.increment_usage_counter(db, user_id, feature_key)
    except Exception as exc:
        logger.warning("usage increment error [%s]: %s", feature_key, exc)
        db.rollback()


# ── Helpers de deduplicação de questões ──────────────────────────────────────

_SEEN_MAX_PER_TOPIC = 200  # máximo de fingerprints guardados por user/tópico
_SEEN_LIMIT_AVOID = 30  # quantas questões recentes passar ao prompt como "evitar"


def _q_fingerprint(text: str) -> str:
    """SHA-1[:16] do texto normalizado — identifica questões duplicadas."""
    norm = re.sub(r"\s+", " ", text.lower().strip())
    return hashlib.sha256(norm.encode("utf-8")).hexdigest()[:16]


def _topic_key(topic: str) -> str:
    """Normaliza o tópico para uso como chave de agrupamento."""
    return re.sub(r"\s+", " ", topic.lower().strip())[:200]


def _load_seen_questions(db: Session, user_id: int, topic_key: str) -> list[str]:
    """Retorna os textos das últimas _SEEN_LIMIT_AVOID questões vistas no tópico."""
    rows = (
        db.query(models.QuizSeenQuestion)
        .filter(
            models.QuizSeenQuestion.user_id == user_id,
            models.QuizSeenQuestion.topic_key == topic_key,
        )
        .order_by(models.QuizSeenQuestion.created_at.desc())
        .limit(_SEEN_LIMIT_AVOID)
        .all()
    )
    return [r.question_text for r in rows]


def _store_seen_questions(
    db: Session, user_id: int, topic_key: str, questions: list[dict]
) -> None:
    """Persiste fingerprints das questões recém-geradas; remove excesso se necessário."""
    try:
        for q in questions:
            text = (q.get("pergunta") or "").strip()
            if not text:
                continue
            fp = _q_fingerprint(text)
            exists = (
                db.query(models.QuizSeenQuestion)
                .filter_by(user_id=user_id, fingerprint=fp)
                .first()
            )
            if not exists:
                db.add(
                    models.QuizSeenQuestion(
                        user_id=user_id,
                        topic_key=topic_key,
                        fingerprint=fp,
                        question_text=text[:500],
                    )
                )

        # Limpeza: mantém apenas os _SEEN_MAX_PER_TOPIC mais recentes por tópico
        count = (
            db.query(func.count(models.QuizSeenQuestion.id))
            .filter(
                models.QuizSeenQuestion.user_id == user_id,
                models.QuizSeenQuestion.topic_key == topic_key,
            )
            .scalar()
        ) or 0
        if count > _SEEN_MAX_PER_TOPIC:
            excess = count - _SEEN_MAX_PER_TOPIC
            oldest_ids = (
                db.query(models.QuizSeenQuestion.id)
                .filter(
                    models.QuizSeenQuestion.user_id == user_id,
                    models.QuizSeenQuestion.topic_key == topic_key,
                )
                .order_by(models.QuizSeenQuestion.created_at.asc())
                .limit(excess)
                .all()
            )
            ids_to_del = [row[0] for row in oldest_ids]
            db.query(models.QuizSeenQuestion).filter(
                models.QuizSeenQuestion.id.in_(ids_to_del)
            ).delete(synchronize_session=False)

        db.commit()
    except Exception as exc:
        logger.warning("quiz/seen store error: %s", exc)
        db.rollback()


# ── Helpers de deduplicação de flashcards ────────────────────────────────────

_FLASHCARD_SEEN_MAX = 150  # max fingerprints stored per user/topic
_FLASHCARD_AVOID_LIMIT = 20  # max fronts sent to AI as avoid list


def _fc_fingerprint(front: str) -> str:
    """SHA-1[:16] of normalised flashcard front text."""
    norm = re.sub(r"\s+", " ", (front or "").strip().lower())
    return hashlib.sha256(norm.encode("utf-8")).hexdigest()[:16]


def _load_seen_flashcard_fronts(db: Session, user_id: int, topic_key: str) -> list[str]:
    """Return up to _FLASHCARD_AVOID_LIMIT recently-seen flashcard fronts for this user/topic."""
    rows = (
        db.query(models.FlashcardSeenSuggestion.front_text)
        .filter(
            models.FlashcardSeenSuggestion.user_id == user_id,
            models.FlashcardSeenSuggestion.topic_key == topic_key,
        )
        .order_by(models.FlashcardSeenSuggestion.id.desc())
        .limit(_FLASHCARD_AVOID_LIMIT)
        .all()
    )
    return [r[0] for r in rows]


def _store_seen_flashcards(
    db: Session, user_id: int, topic_key: str, fronts: list[str]
) -> None:
    """Persist flashcard fronts as seen (upsert, evict oldest beyond cap)."""
    if not fronts:
        return
    try:
        for front in fronts:
            fp = _fc_fingerprint(front)
            exists = (
                db.query(models.FlashcardSeenSuggestion)
                .filter_by(user_id=user_id, fingerprint=fp)
                .first()
            )
            if not exists:
                db.add(
                    models.FlashcardSeenSuggestion(
                        user_id=user_id,
                        topic_key=topic_key,
                        fingerprint=fp,
                        front_text=front[:200],
                    )
                )

        db.commit()

        # Evict oldest beyond cap
        count = (
            db.query(func.count(models.FlashcardSeenSuggestion.id))
            .filter(
                models.FlashcardSeenSuggestion.user_id == user_id,
                models.FlashcardSeenSuggestion.topic_key == topic_key,
            )
            .scalar()
        ) or 0
        if count > _FLASHCARD_SEEN_MAX:
            excess = count - _FLASHCARD_SEEN_MAX
            oldest_ids = (
                db.query(models.FlashcardSeenSuggestion.id)
                .filter(
                    models.FlashcardSeenSuggestion.user_id == user_id,
                    models.FlashcardSeenSuggestion.topic_key == topic_key,
                )
                .order_by(models.FlashcardSeenSuggestion.created_at.asc())
                .limit(excess)
                .all()
            )
            ids_to_del = [row[0] for row in oldest_ids]
            db.query(models.FlashcardSeenSuggestion).filter(
                models.FlashcardSeenSuggestion.id.in_(ids_to_del)
            ).delete(synchronize_session=False)
            db.commit()
    except Exception as exc:
        logger.warning("flashcard/seen store error: %s", exc)
        db.rollback()


# ── /quiz/generate ────────────────────────────────────────────────────────────


class QuizGenerateIn(BaseModel):
    topic: str = Field(max_length=200)
    difficulty: str = Field(default="intermediario", max_length=30)
    quantity: int = Field(default=10, ge=1, le=30)
    provider: str | None = Field(default=None, max_length=30)
    context: str | None = Field(default=None, max_length=50_000)


@router.post("/quiz/generate", dependencies=[Depends(rate_limit(20, 60))])
def generate_quiz(
    body: QuizGenerateIn,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    if not body.topic or not body.topic.strip():
        raise HTTPException(
            status_code=422, detail="O campo 'topic' não pode ser vazio."
        )
    user = _require_user(authorization, db)
    premium_user = _is_premium(user, db)
    if not premium_user:
        _check_quiz_limit(user, db)
    quantity = max(1, min(30, body.quantity))

    # Carrega questões já vistas para evitar repetição no prompt
    tk = _topic_key(body.topic)
    avoid_texts = _load_seen_questions(db, user.id, tk)

    prompt = ai.build_quiz_prompt(
        body.topic, body.difficulty, quantity, body.context, avoid=avoid_texts
    )
    try:
        raw_text, _provider = _call_ai_for_user(
            user,
            db,
            requested_provider=body.provider,
            system_prompt=ai._SYSTEM_QUIZ,
            user_prompt=prompt,
        )
        raw_questions = ai.extract_json_list(raw_text)
        raw_questions = ai.filter_metadata_questions(raw_questions)
        questions = ai.normalize_quiz_questions(raw_questions)
    except HTTPException:
        raise
    except Exception as exc:
        logger.warning("quiz/generate AI error: %s", exc)
        _raise_ai_provider_failure(
            "gerar questoes", normalize_provider(body.provider), exc
        )

    if not questions:
        raise HTTPException(
            status_code=502,
            detail="A IA não retornou questões válidas. Tente novamente.",
        )

    if premium_user:
        _increment_usage(db, user.id, "quiz_generate")
    else:
        allowed, _used = services.consume_daily_limit(
            db,
            user.id,
            "quiz_generate",
            _FREE_QUIZ_DAILY_LIMIT,
        )
        if not allowed:
            raise HTTPException(
                status_code=429,
                detail=(
                    f"Você já gerou {_FREE_QUIZ_DAILY_LIMIT} quizzes hoje. "
                    "Faça upgrade para Premium e tenha quizzes ilimitados."
                ),
            )

    # Persiste fingerprints após reservar a cota para evitar contabilizar falhas.
    _store_seen_questions(db, user.id, tk, questions)

    return {"questions": questions, "topic": body.topic, "difficulty": body.difficulty}


# ── /quiz/submit ──────────────────────────────────────────────────────────────


class QuizAnswerIn(BaseModel):
    question_id: str
    selected_option_id: str | None = None
    is_correct: bool = False


class QuizSubmitIn(BaseModel):
    session_id: str | None = None
    topic: str | None = Field(default=None, max_length=200)
    total: int = Field(default=0, ge=0, le=500)
    correct: int = Field(default=0, ge=0, le=500)
    xp_earned: int = Field(default=0, ge=0, le=100_000)
    time_taken_seconds: int = Field(default=0, ge=0)
    answers: list[QuizAnswerIn] = []


@router.post("/quiz/submit")
def submit_quiz(
    body: QuizSubmitIn,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = _require_user(authorization, db)
    if body.correct > body.total:
        raise HTTPException(
            status_code=422,
            detail="O numero de acertos nao pode ser maior que o total de questoes.",
        )

    event_id = str(body.session_id or uuid.uuid4())
    # M7 — cap duplo: respeita o limite do campo e evita que correct*10 ultrapasse 100k.
    xp_from_correct = min(body.correct * 10, 100_000)
    xp = max(0, min(body.xp_earned, 100_000) if body.xp_earned else xp_from_correct)

    # Idempotente via event_id
    exists = (
        db.query(models.QuizStatsEvent)
        .filter(
            models.QuizStatsEvent.user_id == user.id,
            models.QuizStatsEvent.event_id == event_id,
        )
        .first()
    )
    if exists:
        return {"ok": True, "xp_earned": xp}

    try:
        ev = models.QuizStatsEvent(
            user_id=user.id,
            event_id=event_id,
            questoes_delta=body.total,
            acertos_delta=body.correct,
            xp_delta=xp,
            correta=body.correct,
        )
        db.add(ev)
        # Atualiza daily stats no mesmo commit para evitar estado parcial.
        today = datetime.now(timezone.utc).date()
        daily = (
            db.query(models.QuizStatsDaily)
            .filter(
                models.QuizStatsDaily.user_id == user.id,
                models.QuizStatsDaily.day_key == today,
            )
            .first()
        )
        if daily:
            daily.questoes = int(daily.questoes or 0) + body.total
            daily.acertos = int(daily.acertos or 0) + body.correct
            daily.xp_ganho = int(daily.xp_ganho or 0) + xp
        else:
            db.add(
                models.QuizStatsDaily(
                    user_id=user.id,
                    day_key=today,
                    questoes=body.total,
                    acertos=body.correct,
                    xp_ganho=xp,
                )
            )
        db.execute(
            text("UPDATE users SET xp = COALESCE(xp, 0) + :delta WHERE id = :uid"),
            {"delta": xp, "uid": user.id},
        )
        _update_streak(user, db)
        db.commit()
    except IntegrityError:
        db.rollback()
        existing = (
            db.query(models.QuizStatsEvent)
            .filter(
                models.QuizStatsEvent.user_id == user.id,
                models.QuizStatsEvent.event_id == event_id,
            )
            .first()
        )
        if existing:
            return {"ok": True, "xp_earned": int(existing.xp_delta or 0)}
        raise
    except Exception:
        db.rollback()
        raise

    return {"ok": True, "xp_earned": xp}


def _update_streak(user: models.User, db: Session) -> None:
    # L2 — usa UTC para evitar off-by-one em servidores fora de UTC.
    today = datetime.now(timezone.utc).date()
    last = user.last_activity_day
    if last is None or last < today:
        yesterday = today - timedelta(days=1)
        if last == yesterday:
            user.streak_days = int(user.streak_days or 0) + 1
        elif last != today:
            user.streak_days = 1
        user.last_activity_day = today


# ── /quiz/history ─────────────────────────────────────────────────────────────


@router.get("/quiz/history")
def get_quiz_history(
    limit: int = 20,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = _require_user(authorization, db)
    premium = _is_premium(user, db)

    query = db.query(models.QuizStatsEvent).filter(
        models.QuizStatsEvent.user_id == user.id
    )

    # Usuários free: histórico limitado aos últimos 7 dias
    if not premium:
        cutoff = datetime.now(timezone.utc) - timedelta(days=7)
        query = query.filter(models.QuizStatsEvent.created_at >= cutoff)

    rows = (
        query.order_by(models.QuizStatsEvent.created_at.desc())
        .limit(min(limit, 100 if premium else 50))
        .all()
    )
    return {
        "history": [
            {
                "event_id": r.event_id,
                "total": int(r.questoes_delta or 0),
                "correct": int(r.acertos_delta or 0),
                "xp_earned": int(r.xp_delta or 0),
                "accuracy": round(
                    int(r.acertos_delta or 0) / int(r.questoes_delta or 1) * 100, 1
                ),
                "created_at": r.created_at.isoformat() if r.created_at else None,
            }
            for r in rows
        ],
        "is_premium": premium,
        "history_limited": not premium,  # avisa ao Flutter que o histórico está truncado
    }


# ── /quiz/seen-questions — limpar memória de perguntas ───────────────────────


@router.delete("/quiz/seen-questions")
def clear_seen_questions(
    topic: str | None = None,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    """Remove as perguntas já vistas do usuário.
    - Sem parâmetros: apaga toda a memória.
    - Com ?topic=...: apaga apenas o tópico informado.
    """
    user = _require_user(authorization, db)
    query = db.query(models.QuizSeenQuestion).filter(
        models.QuizSeenQuestion.user_id == user.id
    )
    if topic and topic.strip():
        query = query.filter(models.QuizSeenQuestion.topic_key == _topic_key(topic))
    deleted = query.delete(synchronize_session=False)
    db.commit()
    return {"ok": True, "deleted": deleted}


# ── /simulado/generate ────────────────────────────────────────────────────────


class SimuladoGenerateIn(BaseModel):
    topic: str | None = Field(default=None, max_length=200)
    difficulty: str = Field(default="intermediario", max_length=30)
    quantity: int = Field(default=30, ge=5, le=60)
    provider: str | None = Field(default=None, max_length=30)
    context: str | None = Field(default=None, max_length=50_000)


@router.post("/simulado/generate", dependencies=[Depends(rate_limit(20, 60))])
def generate_simulado(
    body: SimuladoGenerateIn,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = _require_user(authorization, db)
    _check_simulado_limit(user, db)  # ← bloqueia free users no limite
    quantity = max(5, min(60, body.quantity))

    # Deduplicação: carrega questões já vistas para este simulado/tópico
    topic_raw = (body.topic or "concurso").strip()
    tk = "simulado:" + _topic_key(topic_raw)
    avoid_texts = _load_seen_questions(db, user.id, tk)

    prompt = ai.build_simulado_prompt(
        body.topic, body.difficulty, quantity, body.context, avoid=avoid_texts
    )
    try:
        raw_text, _provider = _call_ai_for_user(
            user,
            db,
            requested_provider=body.provider,
            system_prompt=ai._SYSTEM_QUIZ,
            user_prompt=prompt,
        )
        raw_questions = ai.extract_json_list(raw_text)
        raw_questions = ai.filter_metadata_questions(raw_questions)
        questions = ai.normalize_quiz_questions(raw_questions)
    except HTTPException:
        raise
    except Exception as exc:
        logger.warning("simulado/generate AI error: %s", exc)
        _raise_ai_provider_failure(
            "gerar simulado", normalize_provider(body.provider), exc
        )

    if not questions:
        raise HTTPException(
            status_code=502,
            detail="A IA não retornou questões válidas. Tente novamente.",
        )

    # Persiste fingerprints e incrementa contador de uso
    _store_seen_questions(db, user.id, tk, questions)
    if _is_premium(user, db):
        _increment_usage(db, user.id, "simulado_generate")
    else:
        allowed, _used = services.consume_daily_limit(
            db,
            user.id,
            "simulado_generate",
            _FREE_SIMULADO_WEEKLY_LIMIT,
            day_key=_get_week_start(datetime.now(timezone.utc).date()),
        )
        if not allowed:
            raise HTTPException(
                status_code=429,
                detail="Limite semanal de simulados atingido.",
            )

    return {"questions": questions, "topic": body.topic, "difficulty": body.difficulty}


# ── /simulado/submit ──────────────────────────────────────────────────────────


class SimuladoSubmitIn(BaseModel):
    correct: int = Field(default=0, ge=0, le=500)
    total: int = Field(default=0, ge=0, le=500)
    accuracy: float = Field(default=0.0, ge=0.0, le=100.0)
    xp_earned: int = Field(default=0, ge=0, le=100_000)
    time_taken_seconds: int = Field(default=0, ge=0)
    topic: str | None = Field(default=None, max_length=200)
    session_id: str | None = None


@router.post("/simulado/submit")
def submit_simulado(
    body: SimuladoSubmitIn,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    # Reutiliza a mesma lógica do quiz/submit
    submit_body = QuizSubmitIn(
        session_id=body.session_id or str(uuid.uuid4()),
        topic=body.topic,
        total=body.total,
        correct=body.correct,
        xp_earned=body.xp_earned,
        time_taken_seconds=body.time_taken_seconds,
    )
    return submit_quiz(submit_body, authorization, db)


@router.get("/simulado/history")
def get_simulado_history(
    limit: int = 20,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    return get_quiz_history(limit, authorization, db)


# ── /quiz/open/generate ───────────────────────────────────────────────────────


class OpenGenerateIn(BaseModel):
    tema: str
    dificuldade: str = "intermediario"
    contexto_material: str | None = None
    provider: str | None = Field(default=None, max_length=30)


@router.post("/quiz/open/generate", dependencies=[Depends(rate_limit(20, 60))])
def generate_open_question(
    body: OpenGenerateIn,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = _require_user(authorization, db)
    _check_open_quiz_limit(user, db)
    # Build topic key for deduplication
    topic_key = "open:" + re.sub(r"\s+", "_", (body.tema or "").strip().lower())[:80]

    # Load previously seen questions to avoid
    seen = _load_seen_questions(db, user.id, topic_key)

    prompt = ai.build_open_question_prompt(
        body.tema, body.dificuldade, body.contexto_material, avoid=seen
    )
    try:
        raw_text, _provider = _call_ai_for_user(
            user,
            db,
            requested_provider=body.provider,
            system_prompt=ai._SYSTEM_OPEN,
            user_prompt=prompt,
        )
        data = ai.extract_json_object(raw_text)
    except HTTPException:
        raise
    except Exception as exc:
        logger.warning("quiz/open/generate error: %s", exc)
        _raise_ai_provider_failure(
            "gerar questao dissertativa", normalize_provider(body.provider), exc
        )

    if _is_premium(user, db):
        _increment_usage(db, user.id, "open_quiz_generate")
    else:
        allowed, _used = services.consume_daily_limit(
            db,
            user.id,
            "open_quiz_generate",
            _FREE_OPEN_QUIZ_WEEKLY_LIMIT,
            day_key=_get_week_start(datetime.now(timezone.utc).date()),
        )
        if not allowed:
            raise HTTPException(
                status_code=429,
                detail="Limite semanal de questoes dissertativas atingido.",
            )

    # Store the newly generated question to avoid future repetition
    pergunta = data.get("pergunta", "")
    if pergunta:
        _store_seen_questions(db, user.id, topic_key, [{"pergunta": pergunta}])

    return {
        "pergunta": pergunta or f"Explique os principais conceitos de '{body.tema}'.",
        "contexto": data.get("contexto") or "",
        "resposta_esperada": data.get("resposta_esperada") or "",
    }


# ── /quiz/open/grade ──────────────────────────────────────────────────────────


class OpenGradeIn(BaseModel):
    pergunta: str
    resposta_esperada: str
    resposta_aluno: str


@router.post("/quiz/open/grade", dependencies=[Depends(rate_limit(20, 60))])
def grade_open_answer(
    body: OpenGradeIn,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = _require_user(authorization, db)
    if not body.resposta_aluno or not body.resposta_aluno.strip():
        raise HTTPException(
            status_code=422, detail="A resposta do aluno não pode ser vazia."
        )
    prompt = ai.build_grade_prompt(
        body.pergunta, body.resposta_esperada, body.resposta_aluno
    )
    try:
        raw_text, _provider = _call_ai_for_user(
            user,
            db,
            system_prompt=ai._SYSTEM_GRADE,
            user_prompt=prompt,
        )
        data = ai.extract_json_object(raw_text)
    except HTTPException:
        raise
    except Exception as exc:
        logger.warning("quiz/open/grade error: %s", exc)
        raise HTTPException(
            status_code=502, detail="Erro ao avaliar resposta. Tente novamente."
        )

    nota = int(data.get("nota") or 50)
    return {
        "nota": nota,
        "correto": bool(data.get("correto", nota >= 70)),
        "feedback": data.get("feedback") or "Avaliação concluída.",
        "pontos_fortes": data.get("pontos_fortes") or [],
        "pontos_melhorar": data.get("pontos_melhorar") or [],
        "criterios": data.get("criterios") or {},
    }


# ── /study-plan/generate ──────────────────────────────────────────────────────


class StudyPlanIn(BaseModel):
    topics: list[str] = []
    weeks: int = 4
    hours_per_week: float = 10.0
    level: str = "iniciante"
    goal: str | None = None
    provider: str | None = Field(default=None, max_length=30)


@router.post("/study-plan/generate")
def generate_study_plan(
    body: StudyPlanIn,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = _require_user(authorization, db)
    # Build topic key to track previous plan focus areas
    topic_str = "_".join(sorted((body.topics or ["geral"])[:5]))
    topic_key = "studyplan:" + re.sub(r"\s+", "_", topic_str.lower())[:80]

    # Load previously-used focus areas to avoid repetition
    seen_focuses = _load_seen_questions(db, user.id, topic_key)

    prompt = ai.build_study_plan_prompt(
        body.topics,
        body.weeks,
        body.hours_per_week,
        body.level,
        body.goal,
        avoid_focuses=seen_focuses,
    )
    try:
        raw_text, _provider = _call_ai_for_user(
            user,
            db,
            requested_provider=body.provider,
            system_prompt=ai._SYSTEM_PLAN,
            user_prompt=prompt,
        )
        data = ai.extract_json_object(raw_text)
    except HTTPException:
        raise
    except Exception as exc:
        logger.warning("study-plan/generate error: %s", exc)
        _raise_ai_provider_failure(
            "gerar plano de estudos", normalize_provider(body.provider), exc
        )

    # Extract focus topics from the generated plan to avoid next time
    plan_topics = [w.get("foco", "") for w in data.get("semanas", []) if w.get("foco")]
    if plan_topics:
        _store_seen_questions(
            db, user.id, topic_key, [{"pergunta": t} for t in plan_topics[:5]]
        )

    return {
        "titulo": data.get("titulo") or "Plano de Estudos Personalizado",
        "descricao": data.get("descricao") or "",
        "semanas": data.get("semanas") or [],
        "dicas": data.get("dicas") or [],
    }


# ── /library/generate-package ─────────────────────────────────────────────────


class LibraryPackageIn(BaseModel):
    topic: str | None = None
    level: str = "intermediario"
    context: str | None = None
    titulo: str | None = None
    conteudo: str | None = None
    categoria: str | None = None
    provider: str | None = Field(default=None, max_length=30)


@router.post("/library/generate-package")
def generate_library_package(
    body: LibraryPackageIn,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = _require_user(authorization, db)
    topic = (body.topic or body.titulo or "").strip() or "Material da biblioteca"
    context = body.context or body.conteudo
    topic_key = re.sub(r"\s+", "_", topic.lower())[:80]

    # Load seen flashcard fronts for avoid list
    seen_fronts = _load_seen_flashcard_fronts(db, user.id, topic_key)

    prompt = ai.build_library_prompt(
        topic, body.level, context, avoid_fronts=seen_fronts
    )
    try:
        raw_text, _provider = _call_ai_for_user(
            user,
            db,
            requested_provider=body.provider,
            system_prompt=ai._SYSTEM_LIBRARY,
            user_prompt=prompt,
        )
        data = ai.extract_json_object(raw_text)
    except HTTPException:
        raise
    except Exception as exc:
        logger.warning("library/generate error: %s", exc)
        _raise_ai_provider_failure(
            "gerar material da biblioteca", normalize_provider(body.provider), exc
        )

    sanitized = ai.sanitize_library_package_response(
        data,
        topic=topic,
        context=context,
    )

    # Store new flashcard fronts as seen
    new_flashcards = sanitized.get("sugestoes_flashcards") or []
    if new_flashcards:
        flashcard_fronts = [
            fc.get("front", "") for fc in new_flashcards if fc.get("front")
        ]
        _store_seen_flashcards(db, user.id, topic_key, flashcard_fronts)
    if (
        sanitized.get("_strict_relevance")
        and not sanitized.get("topicos_principais")
        and not sanitized.get("sugestoes_flashcards")
        and not sanitized.get("sugestoes_questoes")
    ):
        raise HTTPException(
            status_code=422,
            detail=(
                "A IA nao retornou conteudo aderente ao material selecionado. "
                "Tente outro arquivo ou um recorte menor."
            ),
        )
    sanitized.pop("_strict_relevance", None)
    return sanitized


# ── /ranking/* ────────────────────────────────────────────────────────────────


def _build_ranking_response(user: models.User, db: Session, period: str) -> dict:
    today = datetime.now(timezone.utc).date()
    stats_q = db.query(
        models.QuizStatsDaily.user_id.label("user_id"),
        func.coalesce(func.sum(models.QuizStatsDaily.questoes), 0).label(
            "total_questoes"
        ),
        func.coalesce(func.sum(models.QuizStatsDaily.acertos), 0).label(
            "total_acertos"
        ),
        func.coalesce(func.sum(models.QuizStatsDaily.xp_ganho), 0).label("period_xp"),
    )
    if period == "weekly":
        week_start = today - timedelta(days=today.weekday())
        stats_q = stats_q.filter(models.QuizStatsDaily.day_key >= week_start)
    elif period == "monthly":
        month_start = today.replace(day=1)
        stats_q = stats_q.filter(models.QuizStatsDaily.day_key >= month_start)

    # Group by user and join with users table for name/avatar
    stats_q = (
        stats_q.group_by(models.QuizStatsDaily.user_id)
        .join(models.User, models.User.id == models.QuizStatsDaily.user_id)
        .add_columns(
            models.User.name.label("user_name"),
            models.User.avatar_url.label("avatar_url"),
            models.User.level.label("user_level"),
        )
        .order_by(func.coalesce(func.sum(models.QuizStatsDaily.xp_ganho), 0).desc())
        .limit(100)
    )

    rows = stats_q.all()

    ranking_list = []
    current_user_position: int | None = None

    for position, row in enumerate(rows, start=1):
        entry = {
            "position": position,
            "user_id": row.user_id,
            "user_name": row.user_name or "Usuário",
            "avatar_url": row.avatar_url,
            "user_level": row.user_level or "Bronze",
            "period_xp": int(row.period_xp or 0),
            "total_questoes": int(row.total_questoes or 0),
            "total_acertos": int(row.total_acertos or 0),
        }
        ranking_list.append(entry)
        if row.user_id == user.id:
            current_user_position = position

    return {
        "period": period,
        "ranking": ranking_list,
        "current_user_position": current_user_position,
    }


@router.get("/ranking/{period}")
def get_ranking(
    period: str,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    if period not in ("weekly", "monthly", "alltime"):
        raise HTTPException(
            status_code=400, detail="Período inválido. Use: weekly, monthly, alltime"
        )
    user = _require_user(authorization, db)
    return _build_ranking_response(user, db, period)
