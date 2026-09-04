from __future__ import annotations

import base64
import hashlib
import json
import secrets
from datetime import datetime, timedelta, timezone

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from fastapi import APIRouter, Depends, Header, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from .. import ai_service, models, services
from ..admin_ai import (
    create_master_key,
    mark_key_failure,
    mark_key_success,
    record_admin_audit,
    rotate_master_key,
    serialize_master_key,
    validate_provider,
)
from ..ai_provider_config import default_model_for_provider
from ..database import get_db
from ..deps import authenticate_admin
from ..rate_limit import rate_limit

router = APIRouter(prefix="/admin", tags=["admin-ai"])


class CreateAiKeyIn(BaseModel):
    provider: str = Field(min_length=2, max_length=30)
    label: str = Field(default="", max_length=120)
    api_key: str = Field(min_length=8, max_length=500)
    priority: int = Field(default=100, ge=0, le=10_000)


class UpdateAiKeyIn(BaseModel):
    label: str | None = Field(default=None, max_length=120)
    api_key: str | None = Field(default=None, min_length=8, max_length=500)
    priority: int | None = Field(default=None, ge=0, le=10_000)
    is_active: bool | None = None


class EnrollBiometricCredentialIn(BaseModel):
    credential_id: str = Field(min_length=16, max_length=120)
    public_key: str = Field(min_length=40, max_length=64)
    device_name: str = Field(min_length=1, max_length=120)
    platform: str = Field(min_length=2, max_length=30)


class CreateBiometricChallengeIn(BaseModel):
    credential_id: str = Field(min_length=16, max_length=120)
    scope: str = Field(min_length=3, max_length=80)


class VerifyBiometricChallengeIn(BaseModel):
    challenge_id: str = Field(min_length=16, max_length=80)
    credential_id: str = Field(min_length=16, max_length=120)
    signature: str = Field(min_length=80, max_length=120)


class ReorderAiKeyItemIn(BaseModel):
    id: int = Field(gt=0)
    priority: int = Field(ge=0, le=10_000)


class ReorderAiKeysIn(BaseModel):
    keys: list[ReorderAiKeyItemIn] = Field(min_length=1, max_length=100)


_ADMIN_STEP_UP_SCOPES = {
    "ai_key.create",
    "ai_key.update",
    "ai_key.delete",
    "ai_key.test",
    "ai_key.reorder",
}
_BIOMETRIC_CHALLENGE_TTL_SECONDS = 90
_STEP_UP_TTL_SECONDS = 120


def _admin(
    authorization: str | None,
    db: Session,
) -> models.User:
    return authenticate_admin(authorization, db)


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.tzinfo.utcoffset(value) is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _b64url_decode(value: str) -> bytes:
    raw = str(value or "").strip()
    return base64.urlsafe_b64decode(raw + "=" * (-len(raw) % 4))


def _b64url_encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).decode("ascii").rstrip("=")


def _step_up_token_hash(token: str) -> str:
    return hashlib.sha256(str(token or "").encode("utf-8")).hexdigest()


def _validate_scope(scope: str) -> str:
    normalized = str(scope or "").strip().lower()
    if normalized not in _ADMIN_STEP_UP_SCOPES:
        raise HTTPException(status_code=422, detail="Escopo administrativo invalido")
    return normalized


def _require_admin_step_up(
    actor: models.User,
    current_password: str | None,
    step_up_token: str | None,
    *,
    scope: str,
    db: Session,
) -> None:
    # 1. Se forneceu token de step-up (biométrico/desafio pré-validado), verificar primeiro
    if step_up_token:
        token_hash = _step_up_token_hash(str(step_up_token or "").strip())
        grant = (
            db.query(models.AdminStepUpGrant)
            .filter(
                models.AdminStepUpGrant.token_hash == token_hash,
                models.AdminStepUpGrant.user_id == actor.id,
                models.AdminStepUpGrant.scope == scope,
                models.AdminStepUpGrant.used_at.is_(None),
            )
            .first()
        )
        if grant is not None and _as_utc(grant.expires_at) > _utc_now():
            grant.used_at = _utc_now()
            db.flush()
            return

    # 2. Fallback de senha administrativa direta com rate-limit e verificação segura
    if current_password:
        if services.verify_password(current_password, actor.password_hash):
            return
        raise HTTPException(
            status_code=401,
            detail="Senha administrativa incorreta.",
        )

    raise HTTPException(
        status_code=401,
        detail="Confirme a senha ou a biometria para esta operacao.",
    )


def _source_ip(request: Request) -> str | None:
    forwarded = str(request.headers.get("fly-client-ip") or "").strip()
    if forwarded:
        return forwarded[:64]
    return str(getattr(getattr(request, "client", None), "host", "") or "")[:64] or None


def _get_key_or_404(db: Session, key_id: int) -> models.AiMasterKey:
    row = db.query(models.AiMasterKey).filter(models.AiMasterKey.id == key_id).first()
    if row is None:
        raise HTTPException(status_code=404, detail="Chave nao encontrada")
    return row


@router.get(
    "/biometric-credentials/status",
    dependencies=[Depends(rate_limit(30, 60))],
)
def biometric_credential_status(
    credential_id: str,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    actor = _admin(authorization, db)
    row = (
        db.query(models.AdminBiometricCredential)
        .filter(
            models.AdminBiometricCredential.credential_id == credential_id,
            models.AdminBiometricCredential.user_id == actor.id,
            models.AdminBiometricCredential.is_active == 1,
            models.AdminBiometricCredential.enrolled_auth_version
            == services.current_auth_version(actor),
        )
        .first()
    )
    return {"enrolled": row is not None}


@router.post(
    "/biometric-credentials",
    status_code=201,
    dependencies=[Depends(rate_limit(5, 300))],
)
def enroll_biometric_credential(
    payload: EnrollBiometricCredentialIn,
    request: Request,
    authorization: str | None = Header(default=None, alias="Authorization"),
    current_password: str | None = Header(default=None, alias="X-Admin-Password"),
    step_up_token: str | None = Header(default=None, alias="X-Admin-Step-Up"),
    db: Session = Depends(get_db),
):
    actor = _admin(authorization, db)
    _require_admin_step_up(
        actor,
        current_password,
        step_up_token,
        scope="biometric.enroll",
        db=db,
    )
    try:
        public_key_raw = _b64url_decode(payload.public_key)
        Ed25519PublicKey.from_public_bytes(public_key_raw)
    except (ValueError, TypeError):
        raise HTTPException(status_code=422, detail="Chave publica invalida") from None
    if len(public_key_raw) != 32:
        raise HTTPException(status_code=422, detail="Chave publica invalida")

    credential_id = payload.credential_id.strip()
    row = (
        db.query(models.AdminBiometricCredential)
        .filter(models.AdminBiometricCredential.credential_id == credential_id)
        .first()
    )
    if row is not None and row.user_id != actor.id:
        raise HTTPException(status_code=409, detail="Credencial ja cadastrada")
    if row is None:
        row = models.AdminBiometricCredential(
            credential_id=credential_id,
            user_id=actor.id,
            public_key=_b64url_encode(public_key_raw),
            device_name=payload.device_name.strip(),
            platform=payload.platform.strip().lower(),
            enrolled_auth_version=services.current_auth_version(actor),
            is_active=1,
        )
        db.add(row)
    else:
        row.public_key = _b64url_encode(public_key_raw)
        row.device_name = payload.device_name.strip()
        row.platform = payload.platform.strip().lower()
        row.enrolled_auth_version = services.current_auth_version(actor)
        row.is_active = 1
        row.updated_at = _utc_now()
    record_admin_audit(
        db,
        actor=actor,
        action="biometric.enroll",
        target_type="admin_biometric_credential",
        target_id=credential_id,
        source_ip=_source_ip(request),
        details={"platform": row.platform, "device_name": row.device_name},
    )
    db.commit()
    return {"enrolled": True, "credential_id": credential_id}


@router.delete(
    "/biometric-credentials/{credential_id}",
    dependencies=[Depends(rate_limit(5, 300))],
)
def revoke_biometric_credential(
    credential_id: str,
    request: Request,
    authorization: str | None = Header(default=None, alias="Authorization"),
    current_password: str | None = Header(default=None, alias="X-Admin-Password"),
    step_up_token: str | None = Header(default=None, alias="X-Admin-Step-Up"),
    db: Session = Depends(get_db),
):
    actor = _admin(authorization, db)
    _require_admin_step_up(
        actor,
        current_password,
        step_up_token,
        scope="biometric.revoke",
        db=db,
    )
    row = (
        db.query(models.AdminBiometricCredential)
        .filter(
            models.AdminBiometricCredential.credential_id == credential_id,
            models.AdminBiometricCredential.user_id == actor.id,
        )
        .first()
    )
    if row is None:
        raise HTTPException(status_code=404, detail="Credencial nao encontrada")
    row.is_active = 0
    row.updated_at = _utc_now()
    record_admin_audit(
        db,
        actor=actor,
        action="biometric.revoke",
        target_type="admin_biometric_credential",
        target_id=credential_id,
        source_ip=_source_ip(request),
    )
    db.commit()
    return {"ok": True}


@router.post(
    "/biometric-challenges",
    status_code=201,
    dependencies=[Depends(rate_limit(10, 60))],
)
def create_biometric_challenge(
    payload: CreateBiometricChallengeIn,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    actor = _admin(authorization, db)
    scope = _validate_scope(payload.scope)
    credential = (
        db.query(models.AdminBiometricCredential)
        .filter(
            models.AdminBiometricCredential.credential_id
            == payload.credential_id.strip(),
            models.AdminBiometricCredential.user_id == actor.id,
            models.AdminBiometricCredential.is_active == 1,
            models.AdminBiometricCredential.enrolled_auth_version
            == services.current_auth_version(actor),
        )
        .first()
    )
    if credential is None:
        raise HTTPException(
            status_code=404,
            detail="Biometria nao cadastrada ou expirada neste aparelho.",
        )

    challenge_id = secrets.token_urlsafe(24)
    nonce = secrets.token_urlsafe(32)
    message = (
        f"quiz-vance.admin-step-up.v1:{challenge_id}:"
        f"{credential.credential_id}:{scope}:{nonce}"
    ).encode()
    expires_at = _utc_now() + timedelta(seconds=_BIOMETRIC_CHALLENGE_TTL_SECONDS)
    db.add(
        models.AdminBiometricChallenge(
            challenge_id=challenge_id,
            credential_id=credential.id,
            user_id=actor.id,
            scope=scope,
            challenge=_b64url_encode(message),
            expires_at=expires_at,
        )
    )
    db.commit()
    return {
        "challenge_id": challenge_id,
        "challenge": _b64url_encode(message),
        "expires_in": _BIOMETRIC_CHALLENGE_TTL_SECONDS,
    }


@router.post(
    "/biometric-challenges/verify",
    dependencies=[Depends(rate_limit(10, 60))],
)
def verify_biometric_challenge(
    payload: VerifyBiometricChallengeIn,
    request: Request,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    actor = _admin(authorization, db)
    credential = (
        db.query(models.AdminBiometricCredential)
        .filter(
            models.AdminBiometricCredential.credential_id
            == payload.credential_id.strip(),
            models.AdminBiometricCredential.user_id == actor.id,
            models.AdminBiometricCredential.is_active == 1,
            models.AdminBiometricCredential.enrolled_auth_version
            == services.current_auth_version(actor),
        )
        .first()
    )
    challenge = (
        db.query(models.AdminBiometricChallenge)
        .filter(
            models.AdminBiometricChallenge.challenge_id == payload.challenge_id,
            models.AdminBiometricChallenge.user_id == actor.id,
            models.AdminBiometricChallenge.used_at.is_(None),
        )
        .first()
    )
    if (
        credential is None
        or challenge is None
        or challenge.credential_id != credential.id
        or _as_utc(challenge.expires_at) <= _utc_now()
    ):
        raise HTTPException(status_code=401, detail="Desafio biometrico invalido")

    challenge.used_at = _utc_now()
    try:
        Ed25519PublicKey.from_public_bytes(
            _b64url_decode(credential.public_key)
        ).verify(
            _b64url_decode(payload.signature),
            _b64url_decode(challenge.challenge),
        )
    except (InvalidSignature, ValueError, TypeError):
        record_admin_audit(
            db,
            actor=actor,
            action="biometric.verify",
            target_type="admin_biometric_credential",
            target_id=credential.credential_id,
            result="failure",
            source_ip=_source_ip(request),
            details={"scope": challenge.scope},
        )
        db.commit()
        raise HTTPException(
            status_code=401, detail="Assinatura biometrica invalida"
        ) from None

    raw_token = secrets.token_urlsafe(32)
    expires_at = _utc_now() + timedelta(seconds=_STEP_UP_TTL_SECONDS)
    db.add(
        models.AdminStepUpGrant(
            token_hash=_step_up_token_hash(raw_token),
            user_id=actor.id,
            credential_id=credential.id,
            scope=challenge.scope,
            expires_at=expires_at,
        )
    )
    credential.last_used_at = _utc_now()
    record_admin_audit(
        db,
        actor=actor,
        action="biometric.verify",
        target_type="admin_biometric_credential",
        target_id=credential.credential_id,
        source_ip=_source_ip(request),
        details={"scope": challenge.scope},
    )
    db.commit()
    return {
        "step_up_token": raw_token,
        "scope": challenge.scope,
        "expires_in": _STEP_UP_TTL_SECONDS,
    }


@router.get("/ai-keys", dependencies=[Depends(rate_limit(30, 60))])
def list_ai_keys(
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    _admin(authorization, db)
    rows = (
        db.query(models.AiMasterKey)
        .order_by(models.AiMasterKey.priority.asc(), models.AiMasterKey.id.asc())
        .all()
    )
    return {"keys": [serialize_master_key(row) for row in rows]}


@router.post(
    "/ai-keys/reorder",
    dependencies=[Depends(rate_limit(10, 60))],
)
def reorder_ai_keys(
    payload: ReorderAiKeysIn,
    request: Request,
    authorization: str | None = Header(default=None, alias="Authorization"),
    current_password: str | None = Header(default=None, alias="X-Admin-Password"),
    step_up_token: str | None = Header(default=None, alias="X-Admin-Step-Up"),
    db: Session = Depends(get_db),
):
    actor = _admin(authorization, db)
    _require_admin_step_up(
        actor,
        current_password,
        step_up_token,
        scope="ai_key.reorder",
        db=db,
    )
    ids = [item.id for item in payload.keys]
    if len(set(ids)) != len(ids):
        raise HTTPException(status_code=422, detail="Chaves duplicadas na ordenacao")
    rows = db.query(models.AiMasterKey).filter(models.AiMasterKey.id.in_(ids)).all()
    rows_by_id = {row.id: row for row in rows}
    if len(rows_by_id) != len(ids):
        raise HTTPException(status_code=404, detail="Chave nao encontrada")
    now = _utc_now()
    for item in payload.keys:
        row = rows_by_id[item.id]
        row.priority = item.priority
        row.updated_at = now
    record_admin_audit(
        db,
        actor=actor,
        action="ai_key.reorder",
        target_type="ai_master_key",
        source_ip=_source_ip(request),
        details={"key_ids": ids},
    )
    db.commit()
    return {"ok": True}


@router.post("/ai-keys", status_code=201, dependencies=[Depends(rate_limit(10, 60))])
def add_ai_key(
    payload: CreateAiKeyIn,
    request: Request,
    authorization: str | None = Header(default=None, alias="Authorization"),
    current_password: str | None = Header(default=None, alias="X-Admin-Password"),
    step_up_token: str | None = Header(default=None, alias="X-Admin-Step-Up"),
    db: Session = Depends(get_db),
):
    actor = _admin(authorization, db)
    _require_admin_step_up(
        actor,
        current_password,
        step_up_token,
        scope="ai_key.create",
        db=db,
    )
    row = create_master_key(
        db,
        actor=actor,
        provider=payload.provider,
        label=payload.label,
        api_key=payload.api_key,
        priority=payload.priority,
        source_ip=_source_ip(request),
    )
    db.commit()
    db.refresh(row)
    return serialize_master_key(row)


@router.patch("/ai-keys/{key_id}", dependencies=[Depends(rate_limit(20, 60))])
def update_ai_key(
    key_id: int,
    payload: UpdateAiKeyIn,
    request: Request,
    authorization: str | None = Header(default=None, alias="Authorization"),
    current_password: str | None = Header(default=None, alias="X-Admin-Password"),
    step_up_token: str | None = Header(default=None, alias="X-Admin-Step-Up"),
    db: Session = Depends(get_db),
):
    actor = _admin(authorization, db)
    _require_admin_step_up(
        actor,
        current_password,
        step_up_token,
        scope="ai_key.update",
        db=db,
    )
    row = _get_key_or_404(db, key_id)
    changed: list[str] = []
    if payload.label is not None:
        row.label = payload.label.strip()[:120] or row.label
        changed.append("label")
    if payload.priority is not None:
        row.priority = payload.priority
        changed.append("priority")
    if payload.is_active is not None:
        row.is_active = 1 if payload.is_active else 0
        changed.append("is_active")
    if payload.api_key is not None:
        rotate_master_key(row, api_key=payload.api_key)
        changed.append("api_key_rotated")
    row.updated_at = datetime.now(timezone.utc)
    record_admin_audit(
        db,
        actor=actor,
        action="ai_key.update",
        target_type="ai_master_key",
        target_id=str(row.id),
        source_ip=_source_ip(request),
        details={"fields": changed},
    )
    db.commit()
    db.refresh(row)
    return serialize_master_key(row)


@router.delete("/ai-keys/{key_id}", dependencies=[Depends(rate_limit(10, 60))])
def delete_ai_key(
    key_id: int,
    request: Request,
    authorization: str | None = Header(default=None, alias="Authorization"),
    current_password: str | None = Header(default=None, alias="X-Admin-Password"),
    step_up_token: str | None = Header(default=None, alias="X-Admin-Step-Up"),
    db: Session = Depends(get_db),
):
    actor = _admin(authorization, db)
    _require_admin_step_up(
        actor,
        current_password,
        step_up_token,
        scope="ai_key.delete",
        db=db,
    )
    row = _get_key_or_404(db, key_id)
    record_admin_audit(
        db,
        actor=actor,
        action="ai_key.delete",
        target_type="ai_master_key",
        target_id=str(row.id),
        source_ip=_source_ip(request),
        details={"provider": row.provider, "label": row.label},
    )
    db.delete(row)
    db.commit()
    return {"ok": True}


@router.post("/ai-keys/{key_id}/test", dependencies=[Depends(rate_limit(10, 60))])
def test_ai_key(
    key_id: int,
    request: Request,
    authorization: str | None = Header(default=None, alias="Authorization"),
    current_password: str | None = Header(default=None, alias="X-Admin-Password"),
    step_up_token: str | None = Header(default=None, alias="X-Admin-Step-Up"),
    db: Session = Depends(get_db),
):
    actor = _admin(authorization, db)
    _require_admin_step_up(
        actor,
        current_password,
        step_up_token,
        scope="ai_key.test",
        db=db,
    )
    row = _get_key_or_404(db, key_id)
    from .. import services
    from ..admin_ai import classify_provider_error, provider_error_message
    from ..deps import app_secret

    api_key = (
        services.decrypt_api_key(app_secret(), row.secret_encrypted) or ""
    ).strip()
    if not api_key:
        raise HTTPException(status_code=503, detail="Nao foi possivel abrir a chave")
    started = datetime.now(timezone.utc)
    try:
        ai_service.call_ai(
            validate_provider(row.provider),
            api_key,
            default_model_for_provider(row.provider),
            "Responda de forma curta.",
            "Responda somente OK.",
        )
        latency_ms = int((datetime.now(timezone.utc) - started).total_seconds() * 1000)
        mark_key_success(db, row)
        result = {
            "is_valid": True,
            "message": "Chave funcional",
            "latency_ms": latency_ms,
            "provider_status": 200,
        }
    except Exception as exc:
        latency_ms = int((datetime.now(timezone.utc) - started).total_seconds() * 1000)
        code = classify_provider_error(exc)
        mark_key_failure(db, row, error_code=code)
        result = {
            "is_valid": False,
            "message": provider_error_message(code),
            "latency_ms": latency_ms,
            "error_code": code,
            "provider_status": int(
                getattr(getattr(exc, "response", None), "status_code", 0) or 0
            )
            or None,
        }
    record_admin_audit(
        db,
        actor=actor,
        action="ai_key.test",
        target_type="ai_master_key",
        target_id=str(row.id),
        result="success" if result["is_valid"] else "failure",
        source_ip=_source_ip(request),
        details={"provider": row.provider, "error_code": result.get("error_code")},
    )
    db.commit()
    return result


@router.get("/ai-audit", dependencies=[Depends(rate_limit(20, 60))])
def list_ai_audit(
    limit: int = 50,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    _admin(authorization, db)
    safe_limit = max(1, min(100, int(limit)))
    rows = (
        db.query(models.AdminAuditEvent)
        .order_by(models.AdminAuditEvent.id.desc())
        .limit(safe_limit)
        .all()
    )
    return {
        "events": [
            {
                "id": row.id,
                "actor_user_id": row.actor_user_id,
                "action": row.action,
                "target_type": row.target_type,
                "target_id": row.target_id,
                "result": row.result,
                "source_ip": row.source_ip,
                "details": json.loads(row.details_json) if row.details_json else None,
                "created_at": row.created_at,
            }
            for row in rows
        ]
    }
