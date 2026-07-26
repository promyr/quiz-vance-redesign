"""
User/profile, stats, AI config and billing adapters for the Flutter client.
"""

from __future__ import annotations

import re
from datetime import datetime, timedelta, timezone
from urllib.parse import urlparse

from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, field_validator
from sqlalchemy import and_, case, func, or_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .. import models, services
from ..ai_provider_config import normalize_provider, resolve_model_for_provider
from ..database import get_db
from ..deps import app_secret as _app_secret
from ..deps import require_user as _require_user

router = APIRouter(tags=["user"])

_FREE_QUIZ_DAILY_LIMIT = 5
_FREE_SIMULADO_WEEKLY_LIMIT = 1
_FREE_OPEN_QUIZ_WEEKLY_LIMIT = 1
_DATA_URI_RE = re.compile(
    r"^data:image/(png|jpeg|jpg|webp|gif);base64,[A-Za-z0-9+/=\r\n]+$"
)
_ACHIEVEMENT_CATALOG = {
    "primeira_questao": (
        "Primeira Questao",
        "Complete sua primeira questao",
        "🎯",
        50,
        "questions",
        1,
    ),
    "10_questoes": ("Iniciante", "Complete 10 questoes", "📚", 100, "questions", 10),
    "50_questoes": ("Estudante", "Complete 50 questoes", "🎓", 250, "questions", 50),
    "100_questoes": ("Dedicado", "Complete 100 questoes", "🏆", 500, "questions", 100),
    "streak_3": ("Consistente", "Mantenha sequencia de 3 dias", "🔥", 150, "streak", 3),
    "streak_7": (
        "Comprometido",
        "Mantenha sequencia de 7 dias",
        "⚡",
        350,
        "streak",
        7,
    ),
    "nivel_5": ("Nivel 5", "Alcance o nivel 5", "⭐", 300, "level", 5),
    "nivel_mestre": ("Mestre Supremo", "Alcance o nivel 10", "👑", 1000, "level", 10),
    "xp_100": ("100 XP", "Acumule 100 XP", "💫", 100, "xp", 100),
    "xp_500": ("500 XP", "Acumule 500 XP", "💎", 500, "xp", 500),
}


@router.get("/user/profile")
def get_profile(
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = _require_user(authorization, db)
    plan = db.query(models.UserPlan).filter(models.UserPlan.user_id == user.id).first()
    now = datetime.now(timezone.utc)
    plan_code = "free"
    premium_active = False
    if plan:
        plan_code = str(plan.plan_code or "free")
        if plan.premium_until and plan.premium_until.replace(tzinfo=timezone.utc) > now:
            premium_active = True

    return {
        "id": str(user.id),
        "name": user.name,
        "login_id": user.login_id,
        "email": user.email_id,
        "avatar_url": user.avatar_url,
        "plan_type": "premium" if premium_active else "free",
        "plan_code": plan_code,
        "premium_active": premium_active,
        "xp": int(user.xp or 0),
        "level": str(user.level or "Bronze"),
        "streak_days": int(user.streak_days or 0),
    }


class UpdateProfileIn(BaseModel):
    name: str | None = None
    avatar_url: str | None = None

    @field_validator("avatar_url")
    @classmethod
    def validate_avatar_url(cls, value: str | None) -> str | None:
        if value is None:
            return None
        trimmed = value.strip()
        if not trimmed:
            return ""
        if trimmed.startswith("data:image/"):
            if len(trimmed) > 1_500_000:
                raise ValueError("avatar_url muito longa")
            if not _DATA_URI_RE.match(trimmed):
                raise ValueError("avatar_url invalida")
            return trimmed
        if len(trimmed) > 2048:
            raise ValueError("avatar_url muito longa")
        parsed = urlparse(trimmed)
        if parsed.scheme not in {"http", "https"} or not parsed.netloc:
            raise ValueError("avatar_url invalida")
        return trimmed


def _normalize_requested_login_id(raw: str) -> str:
    try:
        return services.normalize_login_id(raw)
    except ValueError:
        raise HTTPException(
            status_code=422,
            detail="ID invalido. Use 3-40 caracteres com letras, numeros, ponto, underline ou hifen.",
        ) from None


@router.post("/user/profile/update")
def update_profile(
    body: UpdateProfileIn,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = _require_user(authorization, db)
    if body.name and body.name.strip():
        user.name = body.name.strip()
    if body.avatar_url is not None:
        user.avatar_url = body.avatar_url.strip() or None
    db.commit()
    db.refresh(user)
    return {"ok": True, "name": user.name, "avatar_url": user.avatar_url}


@router.get("/user/login-id/availability")
def get_login_id_availability(
    login_id: str,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = _require_user(authorization, db)
    normalized = _normalize_requested_login_id(login_id.strip())
    existing = db.query(models.User).filter(models.User.login_id == normalized).first()
    is_current = bool(existing and int(existing.id) == int(user.id))
    return {
        "login_id": normalized,
        "available": existing is None or is_current,
        "is_current": is_current,
    }


class UpdateLoginIdIn(BaseModel):
    login_id: str
    current_password: str


@router.post("/user/profile/login-id")
def update_login_id(
    body: UpdateLoginIdIn,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = _require_user(authorization, db)
    if not services.verify_password(body.current_password, user.password_hash):
        raise HTTPException(status_code=401, detail="Senha atual incorreta.")
    normalized = _normalize_requested_login_id((body.login_id or "").strip())
    if normalized == str(user.login_id or "").strip():
        return {"ok": True, "unchanged": True, "login_id": normalized}

    existing = (
        db.query(models.User)
        .filter(
            models.User.login_id == normalized,
            models.User.id != user.id,
        )
        .first()
    )
    if existing:
        raise HTTPException(status_code=409, detail="ID ja cadastrado")

    user.login_id = normalized
    services.revoke_user_sessions(db, user, commit=False)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        detail = str(getattr(exc, "orig", exc) or "").lower()
        if (
            ("login_id" in detail)
            or ("users_login_id_key" in detail)
            or ("ix_users_login_id" in detail)
        ):
            raise HTTPException(status_code=409, detail="ID ja cadastrado") from exc
        raise HTTPException(status_code=500, detail="Falha ao atualizar ID.") from exc
    db.refresh(user)
    return {"ok": True, "login_id": user.login_id}


class DeleteAccountIn(BaseModel):
    current_password: str
    confirmation_text: str


def _delete_user_dependents(db: Session, user_id: int) -> None:
    user_scoped_models = [
        models.UserPlan,
        models.PasswordResetToken,
        models.UsageDaily,
        models.Payment,
        models.CheckoutSession,
        models.UserSettings,
        models.QuizStatsDaily,
        models.QuizStatsEvent,
        models.Flashcard,
        models.QuizSeenQuestion,
        models.FlashcardSeenSuggestion,
        models.UserAchievement,
    ]

    for model in user_scoped_models:
        db.query(model).filter(model.user_id == user_id).delete(
            synchronize_session=False
        )


@router.delete("/user/account")
def delete_account(
    body: DeleteAccountIn,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = _require_user(authorization, db)
    if str(body.confirmation_text or "").strip().upper() != "EXCLUIR":
        raise HTTPException(status_code=422, detail="Digite EXCLUIR para confirmar.")
    if not services.verify_password(body.current_password, user.password_hash):
        raise HTTPException(status_code=401, detail="Senha atual incorreta.")

    try:
        _delete_user_dependents(db, int(user.id))
        db.delete(user)
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Nao foi possivel excluir a conta agora. Tente novamente em instantes.",
        ) from exc

    return {"ok": True, "message": "Conta excluida com sucesso."}


def _resolve_is_premium(plan: models.UserPlan | None) -> bool:
    if not plan:
        return False
    if plan.plan_code not in ("premium_30", "premium", "trial"):
        return False
    if plan.premium_until is None:
        return True
    return plan.premium_until.replace(tzinfo=timezone.utc) > datetime.now(timezone.utc)


@router.get("/user/stats")
def get_user_stats(
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = _require_user(authorization, db)
    today_key = datetime.now(timezone.utc).date()
    week_start = today_key - timedelta(days=today_key.weekday())

    stats_row = (
        db.query(
            func.coalesce(func.sum(models.QuizStatsDaily.questoes), 0).label(
                "total_questoes"
            ),
            func.coalesce(func.sum(models.QuizStatsDaily.acertos), 0).label(
                "total_acertos"
            ),
            func.coalesce(
                func.sum(
                    case(
                        (
                            models.QuizStatsDaily.day_key == today_key,
                            models.QuizStatsDaily.questoes,
                        ),
                        else_=0,
                    )
                ),
                0,
            ).label("today_questoes"),
            func.coalesce(
                func.sum(
                    case(
                        (
                            models.QuizStatsDaily.day_key == today_key,
                            models.QuizStatsDaily.acertos,
                        ),
                        else_=0,
                    )
                ),
                0,
            ).label("today_acertos"),
            func.coalesce(
                func.sum(
                    case(
                        (
                            models.QuizStatsDaily.day_key == today_key,
                            models.QuizStatsDaily.xp_ganho,
                        ),
                        else_=0,
                    )
                ),
                0,
            ).label("today_xp"),
        )
        .filter(models.QuizStatsDaily.user_id == user.id)
        .one()
    )

    plan = db.query(models.UserPlan).filter(models.UserPlan.user_id == user.id).first()
    plan_code = str(plan.plan_code if plan else "free")
    is_premium = _resolve_is_premium(plan)

    usage_rows = (
        db.query(
            models.UsageDaily.feature_key.label("feature_key"),
            func.coalesce(func.sum(models.UsageDaily.used_count), 0).label(
                "used_count"
            ),
        )
        .filter(models.UsageDaily.user_id == user.id)
        .filter(
            or_(
                and_(
                    models.UsageDaily.feature_key == "quiz_generate",
                    models.UsageDaily.day_key == today_key,
                ),
                and_(
                    models.UsageDaily.feature_key == "simulado_generate",
                    models.UsageDaily.day_key >= week_start,
                    models.UsageDaily.day_key <= today_key,
                ),
                and_(
                    models.UsageDaily.feature_key == "open_quiz_generate",
                    models.UsageDaily.day_key >= week_start,
                    models.UsageDaily.day_key <= today_key,
                ),
            )
        )
        .group_by(models.UsageDaily.feature_key)
        .all()
    )
    usage_by_feature = {
        str(row.feature_key): int(row.used_count or 0) for row in usage_rows
    }

    total_questoes = int(stats_row.total_questoes or 0)
    total_acertos = int(stats_row.total_acertos or 0)
    total_xp = int(user.xp or 0)
    quiz_used_today = usage_by_feature.get("quiz_generate", 0)
    quiz_limit_today = -1 if is_premium else _FREE_QUIZ_DAILY_LIMIT
    simulado_used_week = usage_by_feature.get("simulado_generate", 0)
    simulado_limit_week = -1 if is_premium else _FREE_SIMULADO_WEEKLY_LIMIT
    open_quiz_used_week = usage_by_feature.get("open_quiz_generate", 0)
    open_quiz_limit_week = -1 if is_premium else _FREE_OPEN_QUIZ_WEEKLY_LIMIT

    return {
        "user_id": user.id,
        "total_questoes": total_questoes,
        "total_acertos": total_acertos,
        "total_xp": total_xp,
        "level": str(user.level or "Bronze"),
        "streak_days": int(user.streak_days or 0),
        "today_questoes": int(stats_row.today_questoes or 0),
        "today_acertos": int(stats_row.today_acertos or 0),
        "today_xp": int(stats_row.today_xp or 0),
        "accuracy": round(total_acertos / total_questoes * 100, 1)
        if total_questoes
        else 0.0,
        "last_activity_day": str(user.last_activity_day)
        if user.last_activity_day
        else None,
        "is_premium": is_premium,
        "plan_code": plan_code,
        "quiz_used_today": quiz_used_today,
        "quiz_limit_today": quiz_limit_today,
        "quiz_remaining_today": max(0, quiz_limit_today - quiz_used_today)
        if quiz_limit_today >= 0
        else -1,
        "simulado_used_week": simulado_used_week,
        "simulado_limit_week": simulado_limit_week,
        "simulado_remaining_week": (
            max(0, simulado_limit_week - simulado_used_week)
            if simulado_limit_week >= 0
            else -1
        ),
        "open_quiz_used_week": open_quiz_used_week,
        "open_quiz_limit_week": open_quiz_limit_week,
        "open_quiz_remaining_week": (
            max(0, open_quiz_limit_week - open_quiz_used_week)
            if open_quiz_limit_week >= 0
            else -1
        ),
    }


@router.get("/user/ai-config")
def get_ai_config(
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = _require_user(authorization, db)
    settings = (
        db.query(models.UserSettings)
        .filter(models.UserSettings.user_id == user.id)
        .first()
    )
    if not settings:
        return {
            "provider": "gemini",
            "model": "gemini-3.5-flash",
            "has_api_key": False,
            "has_api_key_gemini": False,
            "has_api_key_openai": False,
            "has_api_key_groq": False,
            "economia_mode": False,
        }

    active_key = (
        settings.api_key_gemini
        if settings.provider == "gemini"
        else settings.api_key_openai
        if settings.provider == "openai"
        else settings.api_key_groq
        if settings.provider == "groq"
        else settings.api_key
    ) or settings.api_key
    return {
        "provider": settings.provider,
        "model": settings.model,
        "has_api_key": bool(active_key),
        "has_api_key_gemini": bool(settings.api_key_gemini),
        "has_api_key_openai": bool(settings.api_key_openai),
        "has_api_key_groq": bool(settings.api_key_groq),
        "economia_mode": bool(settings.economia_mode),
    }


class AiConfigUpdateIn(BaseModel):
    provider: str = "gemini"
    model: str | None = None
    api_key_gemini: str | None = None
    api_key_openai: str | None = None
    api_key_groq: str | None = None
    economia_mode: bool = False


def _ensure_settings(db: Session, user_id: int) -> models.UserSettings:
    row = (
        db.query(models.UserSettings)
        .filter(models.UserSettings.user_id == user_id)
        .first()
    )
    if not row:
        row = models.UserSettings(user_id=user_id)
        db.add(row)
        db.flush()
    return row


@router.post("/user/ai-config")
def update_ai_config(
    body: AiConfigUpdateIn,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = _require_user(authorization, db)
    app_secret = _app_secret()

    row = _ensure_settings(db, user.id)
    previous_provider = row.provider
    requested_provider = normalize_provider(body.provider)
    row.provider = requested_provider
    row.model = resolve_model_for_provider(
        requested_provider,
        stored_model=row.model,
        stored_provider=previous_provider,
        requested_model=body.model,
    )
    if body.api_key_gemini is not None:
        row.api_key_gemini = services.encrypt_api_key(app_secret, body.api_key_gemini)
    if body.api_key_openai is not None:
        row.api_key_openai = services.encrypt_api_key(app_secret, body.api_key_openai)
    if body.api_key_groq is not None:
        row.api_key_groq = services.encrypt_api_key(app_secret, body.api_key_groq)
    row.economia_mode = 1 if body.economia_mode else 0
    row.updated_at = datetime.now(timezone.utc)

    db.commit()
    db.refresh(row)

    active_key = (
        row.api_key_gemini
        if row.provider == "gemini"
        else row.api_key_openai
        if row.provider == "openai"
        else row.api_key_groq
        if row.provider == "groq"
        else row.api_key
    ) or row.api_key
    return {
        "ok": True,
        "provider": row.provider,
        "model": row.model,
        "has_api_key": bool(active_key),
        "has_api_key_gemini": bool(row.api_key_gemini),
        "has_api_key_openai": bool(row.api_key_openai),
        "has_api_key_groq": bool(row.api_key_groq),
        "economia_mode": bool(row.economia_mode),
    }


@router.get("/billing/plans")
def get_plans():
    return {
        "plans": [
            {
                "code": "free",
                "name": "Grátis",
                "price_cents": 0,
                "currency": "BRL",
                "features": [
                    "5 quizzes por dia",
                    "1 simulado por semana",
                    "1 questão dissertativa por semana",
                    "Flashcards ilimitados",
                    "Modo Infinito bloqueado",
                    "Histórico limitado (7 dias)",
                ],
                "limits": {
                    "quiz_per_day": _FREE_QUIZ_DAILY_LIMIT,
                    "simulado_per_week": _FREE_SIMULADO_WEEKLY_LIMIT,
                    "open_quiz_per_week": _FREE_OPEN_QUIZ_WEEKLY_LIMIT,
                },
            },
            {
                "code": "premium_30",
                "name": "Premium Mensal",
                "price_cents": services.PLAN_PRICES_CENTS["premium_30"],
                "currency": "BRL",
                "features": [
                    "Quizzes ilimitados",
                    "Simulados ilimitados",
                    "Questão dissertativa ilimitada",
                    "Modo Infinito ∞",
                    "Histórico completo",
                    "Ranking global",
                    "Plano de estudos personalizado",
                ],
                "limits": {
                    "quiz_per_day": -1,
                    "simulado_per_week": -1,
                    "open_quiz_per_week": -1,
                },
            },
        ]
    }


@router.get("/billing/status")
def get_billing_status(
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = _require_user(authorization, db)
    plan = db.query(models.UserPlan).filter(models.UserPlan.user_id == user.id).first()
    now = datetime.now(timezone.utc)
    premium_active = False
    premium_until = None
    plan_code = "free"
    if plan:
        plan_code = str(plan.plan_code or "free")
        if plan.premium_until and plan.premium_until.replace(tzinfo=timezone.utc) > now:
            premium_active = True
            premium_until = plan.premium_until.isoformat()
    return {
        "plan_code": plan_code,
        "premium_active": premium_active,
        "premium_until": premium_until,
        "is_premium": premium_active,
    }


class SubscribeIn(BaseModel):
    plan_code: str = "premium_30"
    provider: str = "mercadopago"


@router.post("/billing/subscribe")
def subscribe(
    body: SubscribeIn,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = _require_user(authorization, db)
    return {
        "ok": True,
        "message": "Use /billing/checkout/start para iniciar o pagamento.",
        "user_id": user.id,
        "plan_code": body.plan_code,
    }


def _achievement_to_dict(a: models.UserAchievement) -> dict:
    return {
        "achievement_id": a.achievement_id,
        "title": a.title,
        "description": a.description or "",
        "icon": a.icon or "🏆",
        "xp_reward": int(a.xp_reward or 0),
        "unlocked_at": a.unlocked_at.isoformat() if a.unlocked_at else None,
    }


@router.get("/user/achievements")
def get_achievements(
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = _require_user(authorization, db)
    rows = (
        db.query(models.UserAchievement)
        .filter(models.UserAchievement.user_id == user.id)
        .order_by(models.UserAchievement.unlocked_at.desc())
        .all()
    )
    return {"achievements": [_achievement_to_dict(a) for a in rows]}


class UnlockAchievementIn(BaseModel):
    achievement_id: str
    title: str
    description: str | None = None
    icon: str | None = None
    xp_reward: int = 0


@router.post("/user/achievements/unlock")
def unlock_achievement(
    body: UnlockAchievementIn,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    achievement_id = str(body.achievement_id or "").strip()
    definition = _ACHIEVEMENT_CATALOG.get(achievement_id)
    if definition is None:
        raise HTTPException(status_code=422, detail="Conquista desconhecida.")
    if not body.achievement_id or not body.achievement_id.strip():
        raise HTTPException(
            status_code=422, detail="achievement_id não pode ser vazio."
        )
    user = _require_user(authorization, db)
    title, description, icon, xp_reward, metric, target = definition
    if metric == "questions":
        progress = int(
            db.query(func.coalesce(func.sum(models.QuizStatsDaily.questoes), 0))
            .filter(models.QuizStatsDaily.user_id == user.id)
            .scalar()
            or 0
        )
    elif metric == "streak":
        progress = int(user.streak_days or 0)
    elif metric == "level":
        progress = (int(user.xp or 0) // 100) + 1
    else:
        progress = int(user.xp or 0)
    if progress < target:
        raise HTTPException(
            status_code=409,
            detail="Requisitos da conquista ainda nao foram atingidos.",
        )

    existing = (
        db.query(models.UserAchievement)
        .filter_by(user_id=user.id, achievement_id=body.achievement_id.strip())
        .first()
    )
    if existing:
        return {
            "ok": True,
            "already_unlocked": True,
            "achievement": _achievement_to_dict(existing),
        }

    achievement = models.UserAchievement(
        user_id=user.id,
        achievement_id=body.achievement_id.strip(),
        title=title,
        description=description,
        icon=(body.icon or "🏆").strip(),
        xp_reward=xp_reward,
        notified=0,
    )
    achievement.icon = icon
    db.add(achievement)
    user.xp = int(user.xp or 0) + xp_reward

    db.commit()
    db.refresh(achievement)

    return {
        "ok": True,
        "already_unlocked": False,
        "achievement": _achievement_to_dict(achievement),
    }
