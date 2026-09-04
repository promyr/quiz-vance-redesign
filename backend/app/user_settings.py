"""Persistence and response mapping for per-user application settings."""

from __future__ import annotations

from sqlalchemy.orm import Session

from . import models, schemas


def get_or_create_user_settings(
    db: Session,
    user_id: int,
    *,
    commit: bool = False,
) -> models.UserSettings:
    normalized_user_id = int(user_id)
    row = (
        db.query(models.UserSettings)
        .filter(models.UserSettings.user_id == normalized_user_id)
        .first()
    )
    if row:
        return row

    row = models.UserSettings(
        user_id=normalized_user_id,
        provider="gemini",
        model="gemini-3.5-flash",
        economia_mode=0,
        telemetry_opt_in=0,
    )
    db.add(row)
    if commit:
        db.commit()
        db.refresh(row)
    else:
        db.flush()
    return row


def user_settings_out(
    row: models.UserSettings,
    user_id: int,
) -> schemas.UserSettingsOut:
    return schemas.UserSettingsOut(
        user_id=int(user_id),
        provider=str(row.provider or "gemini"),
        model=str(row.model or "gemini-3.5-flash"),
        api_key=None,
        api_key_gemini=None,
        api_key_groq=None,
        has_api_key=False,
        has_api_key_gemini=False,
        has_api_key_groq=False,
        economia_mode=bool(int(row.economia_mode or 0)),
        telemetry_opt_in=bool(int(row.telemetry_opt_in or 0)),
    )
