"""
app/deps.py - Dependencias FastAPI reutilizaveis entre routers.

Centraliza helpers de autenticacao para evitar duplicacao entre quiz.py,
user.py, flashcard.py e main.py.
"""

from __future__ import annotations

import os

from fastapi import HTTPException
from sqlalchemy.orm import Session

from . import models, services

_APP_SECRET: str = str(os.getenv("APP_BACKEND_SECRET", "") or "").strip()
_SESSION_SECRET: str = str(os.getenv("SESSION_SIGNING_SECRET") or _APP_SECRET).strip()
_SESSION_PREVIOUS_KEYS: tuple[str, ...] = tuple(
    dict.fromkeys(
        [
            *[
                item.strip()
                for item in str(os.getenv("SESSION_SIGNING_PREVIOUS_KEYS") or "").split(
                    ","
                )
                if item.strip()
            ],
            *([_APP_SECRET] if _APP_SECRET and _APP_SECRET != _SESSION_SECRET else []),
        ]
    )
)


def app_secret() -> str:
    return _APP_SECRET


def session_secret() -> str:
    return _SESSION_SECRET


def _verify_with_session_keys(token: str, verifier) -> dict | None:
    for key in (_SESSION_SECRET, *_SESSION_PREVIOUS_KEYS):
        if not key:
            continue
        payload = verifier(key, token)
        if payload:
            return payload
    return None


def extract_bearer_token(authorization: str | None) -> str:
    """Remove o prefixo 'Bearer ' de forma case-insensitive."""
    raw = str(authorization or "").strip()
    if not raw.lower().startswith("bearer "):
        return ""
    return raw[7:].strip()


def _resolve_authenticated_user(
    payload: dict | None, db: Session
) -> tuple[models.User, dict]:
    uid = int((payload or {}).get("uid") or 0)
    if uid <= 0:
        raise HTTPException(status_code=401, detail="Token invalido ou expirado")

    user = db.query(models.User).filter(models.User.id == uid).first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuario nao encontrado")

    if not services.token_matches_user(payload, user):
        raise HTTPException(status_code=401, detail="Token invalido ou expirado")

    return user, dict(payload or {})


def authenticate_access_token(
    authorization: str | None,
    db: Session,
) -> tuple[models.User, dict]:
    """Valida o Bearer token de acesso e retorna user + payload."""
    token = extract_bearer_token(authorization)
    payload = _verify_with_session_keys(token, services.verify_access_token)
    if not payload:
        raise HTTPException(status_code=401, detail="Token invalido ou expirado")
    return _resolve_authenticated_user(payload, db)


def authenticate_refresh_token(
    authorization: str | None,
    db: Session,
) -> tuple[models.User, dict]:
    """Valida token de refresh dentro da janela de tolerancia e retorna user + payload."""
    token = extract_bearer_token(authorization)
    payload = _verify_with_session_keys(token, services.verify_refresh_token)
    if not payload:
        raise HTTPException(status_code=401, detail="Token invalido ou expirado")
    return _resolve_authenticated_user(payload, db)


def require_user(
    authorization: str | None,
    db: Session,
) -> models.User:
    """Valida o JWT Bearer e retorna o User autenticado."""
    user, _payload = authenticate_access_token(authorization, db)
    return user


def require_admin(user: models.User) -> models.User:
    """Autoriza apenas a funcao persistida no banco; nunca infere pelo login."""
    if str(getattr(user, "role", "user") or "user").strip().lower() != "admin":
        raise HTTPException(status_code=403, detail="Acesso administrativo necessario")
    return user


def authenticate_admin(
    authorization: str | None,
    db: Session,
) -> models.User:
    return require_admin(require_user(authorization, db))
