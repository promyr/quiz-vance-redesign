from __future__ import annotations

import json
from datetime import datetime, timezone

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


def _admin(
    authorization: str | None,
    db: Session,
) -> models.User:
    return authenticate_admin(authorization, db)


def _require_admin_step_up(actor: models.User, current_password: str | None) -> None:
    if not current_password or not services.verify_password(
        current_password, actor.password_hash
    ):
        raise HTTPException(
            status_code=401,
            detail="Confirme a senha administrativa para esta operacao.",
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


@router.post("/ai-keys", status_code=201, dependencies=[Depends(rate_limit(10, 60))])
def add_ai_key(
    payload: CreateAiKeyIn,
    request: Request,
    authorization: str | None = Header(default=None, alias="Authorization"),
    current_password: str | None = Header(default=None, alias="X-Admin-Password"),
    db: Session = Depends(get_db),
):
    actor = _admin(authorization, db)
    _require_admin_step_up(actor, current_password)
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
    db: Session = Depends(get_db),
):
    actor = _admin(authorization, db)
    _require_admin_step_up(actor, current_password)
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
    db: Session = Depends(get_db),
):
    actor = _admin(authorization, db)
    _require_admin_step_up(actor, current_password)
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
    db: Session = Depends(get_db),
):
    actor = _admin(authorization, db)
    row = _get_key_or_404(db, key_id)
    from .. import services
    from ..admin_ai import classify_provider_error
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
        }
    except Exception as exc:
        latency_ms = int((datetime.now(timezone.utc) - started).total_seconds() * 1000)
        code = classify_provider_error(exc)
        mark_key_failure(db, row, error_code=code)
        result = {
            "is_valid": False,
            "message": "O provedor recusou a chave ou esta indisponivel",
            "latency_ms": latency_ms,
            "error_code": code,
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
