from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime

from fastapi import HTTPException
from sqlalchemy.orm import Session

from . import models, services
from .ai_provider_config import default_model_for_provider, normalize_provider
from .deps import app_secret

ALLOWED_PROVIDERS = frozenset({"gemini", "groq"})
_BLOCKING_ERROR_CODES = frozenset(
    {"invalid_key", "permission_denied", "quota_exceeded"}
)
_ERROR_CODE_ALIASES = {"rate_limited": "rate_limit"}
_NON_KEY_FAILURE_CODES = frozenset({"payload_too_large"})


@dataclass(frozen=True)
class AiCredentialCandidate:
    provider: str
    model: str
    api_key: str
    key_id: int | None
    source: str


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _as_aware(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    if value.tzinfo is None or value.tzinfo.utcoffset(value) is None:
        return value.replace(tzinfo=timezone.utc)
    return value


def validate_provider(value: str) -> str:
    provider = str(value or "").strip().lower()
    if provider not in ALLOWED_PROVIDERS:
        raise HTTPException(status_code=422, detail="Provedor de IA nao suportado")
    return provider


def _mask_key_suffix(suffix: str) -> str:
    clean = str(suffix or "").strip()[-4:]
    return f"••••••••{clean}" if clean else "••••••••"


def serialize_master_key(row: models.AiMasterKey) -> dict:
    return {
        "id": str(row.id),
        "provider": row.provider,
        "label": row.label,
        "priority": int(row.priority or 0),
        "is_active": bool(row.is_active),
        "masked_key": _mask_key_suffix(row.key_suffix),
        "health_status": row.health_status,
        "failure_count": int(row.failure_count or 0),
        "blocked_until": _as_aware(row.blocked_until),
        "last_tested_at": _as_aware(row.last_tested_at),
        "last_success_at": _as_aware(row.last_success_at),
        "last_error_code": row.last_error_code,
        "created_at": _as_aware(row.created_at),
        "updated_at": _as_aware(row.updated_at),
    }


def list_masked_master_keys(db: Session) -> list[dict]:
    rows = (
        db.query(models.AiMasterKey)
        .order_by(
            models.AiMasterKey.priority.asc(),
            models.AiMasterKey.id.asc(),
        )
        .all()
    )
    return [serialize_master_key(row) for row in rows]


def record_admin_audit(
    db: Session,
    *,
    actor: models.User,
    action: str,
    target_type: str,
    target_id: str | None = None,
    result: str = "success",
    source_ip: str | None = None,
    details: dict | None = None,
) -> None:
    safe_details = {
        str(key): value
        for key, value in (details or {}).items()
        if str(key).lower() not in {"api_key", "secret", "secret_encrypted", "token"}
    }
    db.add(
        models.AdminAuditEvent(
            actor_user_id=actor.id,
            action=str(action or "")[:80],
            target_type=str(target_type or "")[:50],
            target_id=str(target_id)[:80] if target_id is not None else None,
            result=str(result or "success")[:30],
            source_ip=str(source_ip or "")[:64] or None,
            details_json=json.dumps(
                safe_details, ensure_ascii=True, separators=(",", ":")
            )
            if safe_details
            else None,
        )
    )


def create_master_key(
    db: Session,
    *,
    actor: models.User,
    provider: str,
    label: str,
    api_key: str,
    priority: int = 100,
    source_ip: str | None = None,
) -> models.AiMasterKey:
    normalized_provider = validate_provider(provider)
    secret = str(api_key or "").strip()
    if len(secret) < 8 or len(secret) > 500:
        raise HTTPException(status_code=422, detail="Chave de API invalida")
    safe_label = (
        str(label or "").strip()[:120] or f"Chave {normalized_provider.upper()}"
    )
    encrypted = services.encrypt_api_key(app_secret(), secret)
    if not encrypted:
        raise HTTPException(status_code=503, detail="Cofre de chaves indisponivel")

    row = models.AiMasterKey(
        provider=normalized_provider,
        label=safe_label,
        secret_encrypted=encrypted,
        key_suffix=secret[-4:],
        priority=max(0, min(10_000, int(priority))),
        is_active=1,
        health_status="unknown",
        created_by_user_id=actor.id,
    )
    db.add(row)
    db.flush()
    record_admin_audit(
        db,
        actor=actor,
        action="ai_key.create",
        target_type="ai_master_key",
        target_id=str(row.id),
        source_ip=source_ip,
        details={"provider": normalized_provider, "label": safe_label},
    )
    return row


def rotate_master_key(
    row: models.AiMasterKey,
    *,
    api_key: str,
) -> None:
    secret = str(api_key or "").strip()
    if len(secret) < 8 or len(secret) > 500:
        raise HTTPException(status_code=422, detail="Chave de API invalida")
    encrypted = services.encrypt_api_key(app_secret(), secret)
    if not encrypted:
        raise HTTPException(status_code=503, detail="Cofre de chaves indisponivel")
    row.secret_encrypted = encrypted
    row.key_suffix = secret[-4:]
    row.failure_count = 0
    row.blocked_until = None
    row.health_status = "unknown"
    row.last_error_code = None
    row.updated_at = _utc_now()


def _is_available(row: models.AiMasterKey, now: datetime) -> bool:
    if not bool(row.is_active):
        return False
    blocked_until = _as_aware(row.blocked_until)
    return blocked_until is None or blocked_until <= now


def select_master_key_candidates(
    db: Session,
    *,
    preferred_provider: str | None = None,
) -> list[AiCredentialCandidate]:
    preferred = normalize_provider(preferred_provider)
    provider_order = [preferred] + [
        provider for provider in ("groq", "gemini") if provider != preferred
    ]
    rank = {provider: index for index, provider in enumerate(provider_order)}
    now = _utc_now()
    rows = db.query(models.AiMasterKey).all()
    available = [row for row in rows if _is_available(row, now)]
    available.sort(
        key=lambda row: (
            rank.get(row.provider, len(rank)),
            int(row.priority or 0),
            int(row.failure_count or 0),
            int(row.id or 0),
        )
    )

    candidates: list[AiCredentialCandidate] = []
    for row in available:
        api_key = (
            services.decrypt_api_key(app_secret(), row.secret_encrypted) or ""
        ).strip()
        if not api_key:
            continue
        candidates.append(
            AiCredentialCandidate(
                provider=row.provider,
                model=default_model_for_provider(row.provider),
                api_key=api_key,
                key_id=row.id,
                source="server_pool",
            )
        )
    return candidates


def mark_key_success(db: Session, row: models.AiMasterKey) -> None:
    now = _utc_now()
    row.health_status = "healthy"
    row.failure_count = 0
    row.blocked_until = None
    row.last_error_code = None
    row.last_success_at = now
    row.last_tested_at = now
    row.updated_at = now
    db.flush()


def mark_key_failure(
    db: Session,
    row: models.AiMasterKey,
    *,
    error_code: str,
    retry_after_seconds: int | None = None,
) -> None:
    now = _utc_now()
    code = str(error_code or "provider_error").strip().lower()[:50]
    code = _ERROR_CODE_ALIASES.get(code, code)
    if code in _NON_KEY_FAILURE_CODES:
        return
    row.failure_count = int(row.failure_count or 0) + 1
    row.last_error_code = code
    row.last_tested_at = now
    row.health_status = "blocked" if code in _BLOCKING_ERROR_CODES else "degraded"
    if code in _BLOCKING_ERROR_CODES:
        minutes = min(60, 5 * (2 ** min(row.failure_count - 1, 3)))
        row.blocked_until = now + timedelta(minutes=minutes)
    elif code == "rate_limit":
        fallback_seconds = 60 * (2 ** min(row.failure_count - 1, 4))
        cooldown_seconds = max(
            fallback_seconds,
            int(retry_after_seconds or 0),
        )
        row.blocked_until = now + timedelta(
            seconds=min(60 * 60, cooldown_seconds)
        )
    elif row.failure_count >= 3:
        row.blocked_until = now + timedelta(minutes=2)
    row.updated_at = now
    db.flush()


def classify_provider_error(exc: Exception) -> str:
    response = getattr(exc, "response", None)
    status = int(getattr(response, "status_code", 0) or 0)
    if status == 413:
        return "payload_too_large"
    if status == 429:
        return "rate_limit"
    if status == 401:
        return "invalid_key"
    if status == 403:
        return "permission_denied"
    if status >= 500:
        return "provider_unavailable"
    if isinstance(exc, TimeoutError):
        return "timeout"
    return "provider_error"


def provider_error_message(error_code: str | None) -> str:
    code = _ERROR_CODE_ALIASES.get(
        str(error_code or "provider_error").strip().lower(),
        str(error_code or "provider_error").strip().lower(),
    )
    return {
        "invalid_key": "A chave foi recusada pelo provedor.",
        "permission_denied": "A chave nao possui permissao para este provedor.",
        "quota_exceeded": "A cota contratada desta chave foi atingida.",
        "rate_limit": "O provedor limitou temporariamente as requisicoes.",
        "provider_unavailable": "O provedor esta temporariamente indisponivel.",
        "timeout": "O provedor demorou demais para responder.",
        "payload_too_large": "A requisicao excedeu o limite do provedor.",
    }.get(code, "Nao foi possivel concluir o teste no provedor.")


def provider_retry_after_seconds(exc: Exception) -> int | None:
    response = getattr(exc, "response", None)
    headers = getattr(response, "headers", None)
    if not headers:
        return None
    value = str(headers.get("Retry-After") or "").strip()
    if not value:
        return None
    try:
        return max(0, min(60 * 60, int(float(value))))
    except (TypeError, ValueError):
        try:
            retry_at = parsedate_to_datetime(value)
        except (TypeError, ValueError, OverflowError):
            return None
        if retry_at.tzinfo is None:
            retry_at = retry_at.replace(tzinfo=timezone.utc)
        seconds = int((retry_at - _utc_now()).total_seconds())
        return max(0, min(60 * 60, seconds))
