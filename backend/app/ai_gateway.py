from __future__ import annotations

import logging
import os
from collections.abc import Callable, Sequence

from sqlalchemy.orm import Session

from . import ai_service, models
from .admin_ai import (
    AiCredentialCandidate,
    classify_provider_error,
    mark_key_failure,
    mark_key_success,
    provider_retry_after_seconds,
    select_master_key_candidates,
)
from .ai_provider_config import normalize_provider, resolve_model_for_provider

AiCall = Callable[..., str]
logger = logging.getLogger(__name__)
ENV_KEY_NAMES = {
    "gemini": "GEMINI_API_KEY",
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

    candidates.extend(select_master_key_candidates(db, preferred_provider=preferred))
    provider_order = [preferred, *[name for name in ENV_KEY_NAMES if name != preferred]]
    for provider in provider_order:
        env_key = os.getenv(ENV_KEY_NAMES[provider], "").strip()
        if not env_key:
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
    max_output_tokens: int | None = None,
    call: AiCall = ai_service.call_ai,
) -> tuple[str, AiCredentialCandidate]:
    last_error: Exception | None = None
    for candidate in candidates:
        try:
            if max_output_tokens is None:
                text = call(
                    candidate.provider,
                    candidate.api_key,
                    candidate.model,
                    system_prompt,
                    user_prompt,
                )
            else:
                text = call(
                    candidate.provider,
                    candidate.api_key,
                    candidate.model,
                    system_prompt,
                    user_prompt,
                    max_output_tokens=max_output_tokens,
                )
            if candidate.key_id is not None:
                row = db.get(models.AiMasterKey, candidate.key_id)
                if row is not None:
                    mark_key_success(db, row)
                    db.commit()
            return text, candidate
        except Exception as exc:  # noqa: BLE001 - isola qualquer SDK de provedor
            last_error = exc
            error_code = classify_provider_error(exc)
            logger.warning(
                "ai_provider_candidate_failed",
                extra={
                    "provider": candidate.provider,
                    "source": candidate.source,
                    "key_id": candidate.key_id,
                    "error_code": error_code,
                    "provider_status": int(
                        getattr(
                            getattr(exc, "response", None),
                            "status_code",
                            0,
                        )
                        or 0
                    ),
                },
            )
            if candidate.key_id is not None:
                row = db.get(models.AiMasterKey, candidate.key_id)
                if row is not None:
                    mark_key_failure(
                        db,
                        row,
                        error_code=error_code,
                        retry_after_seconds=provider_retry_after_seconds(exc),
                    )
                    db.commit()

    if last_error is not None:
        raise last_error
    raise RuntimeError("Nenhuma credencial de IA ativa no servidor")
