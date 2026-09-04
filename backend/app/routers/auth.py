"""
Flutter-compatible authentication endpoints.
"""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import or_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .. import models, services
from ..database import get_db
from ..deps import authenticate_refresh_token
from ..deps import require_user as _require_user
from ..deps import session_secret as _session_secret
from ..rate_limit import rate_limit

router = APIRouter(prefix="/auth", tags=["auth"])


class LoginIn(BaseModel):
    login_id: str | None = None
    id: str | None = None
    email: str | None = None
    email_id: str | None = None
    password: str = Field(min_length=1, max_length=128)


class RegisterIn(BaseModel):
    name: str
    login_id: str | None = None
    id: str | None = None
    email: str | None = None
    email_id: str | None = None
    password: str = Field(min_length=8, max_length=128)


def _resolve_login_identifier(body: LoginIn) -> str:
    raw = (body.login_id or body.id or body.email or body.email_id or "").strip()
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


def _resolve_register_login_id(body: RegisterIn) -> str:
    raw = (body.login_id or body.id or "").strip()
    if not raw:
        raise HTTPException(status_code=422, detail="ID obrigatorio")
    try:
        return services.normalize_login_id(raw)
    except ValueError:
        raise HTTPException(
            status_code=422,
            detail="ID invalido. Use 3-40 caracteres com letras, numeros, ponto, underline ou hifen.",
        ) from None


def _resolve_register_email(body: RegisterIn) -> str:
    raw = (body.email or body.email_id or "").strip()
    if not raw:
        raise HTTPException(status_code=422, detail="E-mail obrigatorio")
    try:
        return services.normalize_email_id(raw)
    except ValueError:
        raise HTTPException(status_code=422, detail="E-mail invalido") from None


def _user_to_dict(
    user: models.User,
    plan: models.UserPlan | None,
    token: str | None = None,
) -> dict:
    now = datetime.now(timezone.utc)
    premium_active = False
    premium_until = None
    plan_code = "free"
    if plan:
        plan_code = str(plan.plan_code or "free")
        if plan.premium_until and plan.premium_until.replace(tzinfo=timezone.utc) > now:
            premium_active = True
            premium_until = plan.premium_until.isoformat()

    auth_payload = {}
    if token:
        auth_payload = {
            "access_token": token,
            "refresh_token": services.create_refresh_token(
                _session_secret(),
                user.id,
                user.email_id,
                services.current_auth_version(user),
            ),
            "token_type": "bearer",
        }
    return {
        "id": str(user.id),
        "user_id": user.id,
        "name": user.name,
        "login_id": user.login_id,
        "email": user.email_id,
        "email_id": user.email_id,
        "role": str(getattr(user, "role", "user") or "user"),
        "avatar_url": user.avatar_url,
        "xp": int(user.xp or 0),
        "level": str(user.level or "Bronze"),
        "streak_days": int(user.streak_days or 0),
        "plan_type": plan_code,
        "plan_code": plan_code,
        "premium_active": premium_active,
        "premium_until": premium_until,
        **auth_payload,
    }


def _maybe_rehash_password(db: Session, user: models.User, raw_password: str) -> None:
    if not services.password_needs_rehash(user.password_hash):
        return
    user.password_hash = services.hash_password(raw_password)
    db.commit()
    db.refresh(user)


@router.post(
    "/legacy/login", include_in_schema=False, dependencies=[Depends(rate_limit(15, 60))]
)
def login(body: LoginIn, db: Session = Depends(get_db)):
    app_secret = _session_secret()
    identifier = _resolve_login_identifier(body)

    user = (
        db.query(models.User)
        .filter(
            or_(
                models.User.login_id == identifier,
                models.User.email_id == identifier,
            )
        )
        .first()
    )
    if not user or not services.verify_password(body.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Credenciais invalidas")

    _maybe_rehash_password(db, user, body.password)

    plan = db.query(models.UserPlan).filter(models.UserPlan.user_id == user.id).first()
    token = services.create_access_token(
        app_secret,
        user.id,
        user.email_id,
        services.current_auth_version(user),
    )
    return _user_to_dict(user, plan, token)


@router.post(
    "/legacy/register",
    include_in_schema=False,
    dependencies=[Depends(rate_limit(5, 60))],
)
def register(body: RegisterIn, db: Session = Depends(get_db)):
    app_secret = _session_secret()
    name = (body.name or "").strip()
    if not name:
        raise HTTPException(status_code=422, detail="Nome obrigatorio")

    login_id = _resolve_register_login_id(body)
    email = _resolve_register_email(body)

    existing_login = (
        db.query(models.User).filter(models.User.login_id == login_id).first()
    )
    if existing_login:
        raise HTTPException(status_code=409, detail="ID ja cadastrado")

    existing_email = db.query(models.User).filter(models.User.email_id == email).first()
    if existing_email:
        raise HTTPException(status_code=409, detail="E-mail ja cadastrado")

    user = models.User(
        name=name,
        login_id=login_id,
        email_id=email,
        password_hash=services.hash_password(body.password),
    )
    db.add(user)
    try:
        db.flush()
        plan = models.UserPlan(user_id=user.id, plan_code="free")
        db.add(plan)
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
        if ("email_id" in detail) or ("users_email_id_key" in detail):
            raise HTTPException(status_code=409, detail="E-mail ja cadastrado") from exc
        raise HTTPException(status_code=500, detail="Falha ao criar usuario.") from exc
    db.refresh(user)

    services.grant_initial_trial(db, user.id)
    plan = db.query(models.UserPlan).filter(models.UserPlan.user_id == user.id).first()

    token = services.create_access_token(
        app_secret,
        user.id,
        user.email_id,
        services.current_auth_version(user),
    )
    return _user_to_dict(user, plan, token)


@router.get("/me", dependencies=[Depends(rate_limit(60, 60))])
def get_me(
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = _require_user(authorization, db)
    plan = db.query(models.UserPlan).filter(models.UserPlan.user_id == user.id).first()
    return _user_to_dict(user, plan)


@router.post("/logout")
def logout(
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = _require_user(authorization, db)
    services.revoke_user_sessions(db, user)
    return {"ok": True, "message": "Logout realizado com sucesso"}


@router.post("/refresh", dependencies=[Depends(rate_limit(20, 60))])
def refresh_token(
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    app_secret = _session_secret()
    user, _payload = authenticate_refresh_token(authorization, db)
    new_token = services.create_access_token(
        app_secret,
        user.id,
        user.email_id,
        services.current_auth_version(user),
    )
    return {
        "access_token": new_token,
        "refresh_token": services.create_refresh_token(
            app_secret,
            user.id,
            user.email_id,
            services.current_auth_version(user),
        ),
        "token_type": "bearer",
    }
