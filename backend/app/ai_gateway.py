from __future__ import annotations

import os
from collections.abc import Callable, Sequence

from sqlalchemy.orm import Session

from . import ai_service, models, services
from .admin_ai import (
    AiCredentialCandidate,
    classify_provider_error,
    mark_key_failure,
    mark_key_success,
    select_master_key_candidates,
)
from .ai_provider_config import normalize_provider, resolve_model_for_provider
from .deps import app_secret

AiCall = Callable[[str, str, str, str, str], str]
ENV_KEY_NAMES = {
    "gemini": "GEMINI_API_KEY",
    "openai": "OPENAI_API_KEY",
    "groq": "GROQ_API_KEY",
}


def build_ai_candidates(
    user: models.User,
    db: Session,
    *,
    requested_provider: str | None = None,
) -> list[AiCredentialCandidate]:
    settings = (
        db.query(models.UserSettings)
        .filter(models.UserSettings.user_id == user.id)
        .first()
    )
    stored_provider = normalize_provider(
        settings.provider if settings is not None else requested_provider
    )
    preferred = normalize_provider(requested_provider or stored_provider)
    candidates: list[AiCredentialCandidate] = []

    if settings is not None:
        key_map = {
            "gemini": settings.api_key_gemini,
            "openai": settings.api_key_openai,
            "groq": settings.api_key_groq,
        }
        encrypted_key = key_map.get(preferred) or settings.api_key or ""
        personal_key = (
            services.decrypt_api_key(app_secret(), encrypted_key) or ""
        ).strip()
        if personal_key:
            candidates.append(
                AiCredentialCandidate(
                    provider=preferred,
                    model=resolve_model_for_provider(
                        preferred,
                        stored_model=settings.model,
                        stored_provider=stored_provider,
                    ),
                    api_key=personal_key,
                    key_id=None,
                    source="user",
                )
            )

    candidates.extend(select_master_key_candidates(db, preferred_provider=preferred))
    database_providers = {
        candidate.provider
        for candidate in candidates
        if candidate.source == "server_pool"
    }
    provider_order = [preferred, *[name for name in ENV_KEY_NAMES if name != preferred]]
    for provider in provider_order:
        env_key = os.getenv(ENV_KEY_NAMES[provider], "").strip()
        if not env_key or provider in database_providers:
            continue
        candidates.append(
            AiCredentialCandidate(
                provider=provider,
                model=resolve_model_for_provider(provider, stored_model=None),
                api_key=env_key,
                key_id=None,
                source="server_env",
            )
        )
    return candidates


def call_ai_with_fallback(
    db: Session,
    candidates: Sequence[AiCredentialCandidate],
    *,
    system_prompt: str,
    user_prompt: str,
    call: AiCall = ai_service.call_ai,
) -> tuple[str, AiCredentialCandidate]:
    last_error: Exception | None = None
    for candidate in candidates:
        try:
            text = call(
                candidate.provider,
                candidate.api_key,
                candidate.model,
                system_prompt,
                user_prompt,
            )
            if candidate.key_id is not None:
                row = db.get(models.AiMasterKey, candidate.key_id)
                if row is not None:
                    mark_key_success(db, row)
                    db.commit()
            return text, candidate
        except Exception as exc:  # noqa: BLE001 - isola qualquer SDK de provedor
            last_error = exc
            if candidate.key_id is not None:
                row = db.get(models.AiMasterKey, candidate.key_id)
                if row is not None:
                    mark_key_failure(
                        db,
                        row,
                        error_code=classify_provider_error(exc),
                    )
                    db.commit()

    if last_error is not None:
        raise last_error
    raise RuntimeError("Nenhuma credencial de IA ativa no servidor")
