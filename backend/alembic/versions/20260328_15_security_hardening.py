"""security hardening for auth, user settings and user-owned rows

Revision ID: 20260328_15
Revises: 20260328_14
Create Date: 2026-03-28

Adiciona auth_version aos usuarios, regrava credenciais legadas de IA em
formato criptografado e atualiza FKs user_id para ON DELETE CASCADE.
"""

from __future__ import annotations

import base64
import os
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from sqlalchemy import inspect, text


revision: str = "20260328_15"
down_revision: Union[str, Sequence[str], None] = "20260328_14"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SECRET_PREFIX = "enc:v1:"
_HKDF_INFO = b"quiz-vance:user-settings:api-keys:v1"
_USER_SETTING_COLUMNS = (
    "api_key",
    "api_key_gemini",
    "api_key_openai",
    "api_key_groq",
)
_USER_FK_TABLES = (
    "user_plan",
    "password_reset_tokens",
    "usage_daily",
    "payments",
    "checkout_sessions",
    "user_settings",
    "quiz_stats_daily",
    "quiz_stats_events",
    "flashcards",
    "quiz_seen_questions",
    "user_achievements",
)


def _derive_fernet(app_secret: str) -> Fernet:
    hkdf = HKDF(
        algorithm=hashes.SHA256(),
        length=32,
        salt=None,
        info=_HKDF_INFO,
    )
    material = hkdf.derive(app_secret.encode("utf-8"))
    return Fernet(base64.urlsafe_b64encode(material))


def _encrypt_secret(fernet: Fernet, value: str) -> str:
    stripped = str(value or "").strip()
    if not stripped:
        return ""
    if stripped.startswith(SECRET_PREFIX):
        return stripped
    token = fernet.encrypt(stripped.encode("utf-8")).decode("utf-8")
    return f"{SECRET_PREFIX}{token}"


def _ensure_auth_version_column(bind) -> None:
    inspector = inspect(bind)
    user_columns = {col["name"] for col in inspector.get_columns("users")}
    if "auth_version" not in user_columns:
        op.add_column(
            "users",
            sa.Column("auth_version", sa.Integer(), nullable=False, server_default="0"),
        )
    bind.execute(text("UPDATE users SET auth_version = 0 WHERE auth_version IS NULL"))


def _encrypt_user_settings(bind) -> None:
    inspector = inspect(bind)
    settings_columns = {col["name"] for col in inspector.get_columns("user_settings")}
    target_columns = [col for col in _USER_SETTING_COLUMNS if col in settings_columns]
    if not target_columns:
        return

    select_sql = text(
        f"SELECT id, {', '.join(target_columns)} FROM user_settings"
    )
    rows = bind.execute(select_sql).mappings().all()

    plaintext_rows: list[dict[str, object]] = []
    for row in rows:
        updates: dict[str, str] = {}
        for column in target_columns:
            raw = row.get(column)
            cleaned = str(raw or "").strip()
            if not cleaned or cleaned.startswith(SECRET_PREFIX):
                continue
            updates[column] = cleaned
        if updates:
            updates["id"] = row["id"]
            plaintext_rows.append(updates)

    if not plaintext_rows:
        return

    app_secret = str(os.getenv("APP_BACKEND_SECRET") or "").strip()
    if not app_secret:
        raise RuntimeError(
            "APP_BACKEND_SECRET obrigatorio para migrar api keys legadas em texto plano."
        )

    fernet = _derive_fernet(app_secret)
    for row in plaintext_rows:
        assignments: list[str] = []
        params: dict[str, object] = {"id": row["id"]}
        for column in target_columns:
            if column not in row:
                continue
            assignments.append(f"{column} = :{column}")
            params[column] = _encrypt_secret(fernet, str(row[column] or ""))
        if not assignments:
            continue
        bind.execute(
            text(
                f"UPDATE user_settings SET {', '.join(assignments)} WHERE id = :id"
            ),
            params,
        )


def _rebuild_user_fk_constraints(bind) -> None:
    if str(bind.dialect.name or "").lower() != "postgresql":
        return

    inspector = inspect(bind)
    existing_tables = set(inspector.get_table_names())
    for table_name in _USER_FK_TABLES:
        if table_name not in existing_tables:
            continue
        constraint_name = f"{table_name}_user_id_fkey"
        bind.execute(
            text(
                f'ALTER TABLE "{table_name}" DROP CONSTRAINT IF EXISTS "{constraint_name}"'
            )
        )
        bind.execute(
            text(
                f'ALTER TABLE "{table_name}" '
                f'ADD CONSTRAINT "{constraint_name}" '
                "FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE"
            )
        )


def upgrade() -> None:
    bind = op.get_bind()
    _ensure_auth_version_column(bind)
    _encrypt_user_settings(bind)
    _rebuild_user_fk_constraints(bind)


def downgrade() -> None:
    bind = op.get_bind()

    if str(bind.dialect.name or "").lower() == "postgresql":
        inspector = inspect(bind)
        existing_tables = set(inspector.get_table_names())
        for table_name in _USER_FK_TABLES:
            if table_name not in existing_tables:
                continue
            constraint_name = f"{table_name}_user_id_fkey"
            bind.execute(
                text(
                    f'ALTER TABLE "{table_name}" DROP CONSTRAINT IF EXISTS "{constraint_name}"'
                )
            )
            bind.execute(
                text(
                    f'ALTER TABLE "{table_name}" '
                    f'ADD CONSTRAINT "{constraint_name}" '
                    "FOREIGN KEY (user_id) REFERENCES users (id)"
                )
            )

    inspector = inspect(bind)
    user_columns = {col["name"] for col in inspector.get_columns("users")}
    if "auth_version" in user_columns:
        op.drop_column("users", "auth_version")
