"""validate security schema and add distributed rate-limit buckets

Revision ID: 20260725_18
Revises: 20260725_17
Create Date: 2026-07-25
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy import inspect

revision: str = "20260725_18"
down_revision: Union[str, Sequence[str], None] = "20260725_17"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_REQUIRED_COLUMNS = {
    "users": {"id", "login_id", "auth_version", "role"},
    "ai_master_keys": {
        "id",
        "provider",
        "secret_encrypted",
        "priority",
        "is_active",
        "created_by_user_id",
    },
    "admin_audit_events": {
        "id",
        "actor_user_id",
        "action",
        "target_type",
        "created_at",
    },
}


def _assert_complete_security_schema(bind) -> None:
    inspector = inspect(bind)
    tables = set(inspector.get_table_names())
    for table, required in _REQUIRED_COLUMNS.items():
        if table not in tables:
            raise RuntimeError(f"schema_incomplete:missing_table:{table}")
        actual = {str(column["name"]) for column in inspector.get_columns(table)}
        missing = sorted(required - actual)
        if missing:
            raise RuntimeError(
                f"schema_incomplete:{table}:missing_columns:{','.join(missing)}"
            )


def upgrade() -> None:
    bind = op.get_bind()
    _assert_complete_security_schema(bind)
    op.create_table(
        "rate_limit_buckets",
        sa.Column("bucket_key", sa.String(length=64), primary_key=True),
        sa.Column("window_start", sa.Integer(), nullable=False),
        sa.Column("request_count", sa.Integer(), nullable=False),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
    )
    op.create_index(
        "ix_rate_limit_buckets_expires_at",
        "rate_limit_buckets",
        ["expires_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        "ix_rate_limit_buckets_expires_at",
        table_name="rate_limit_buckets",
    )
    op.drop_table("rate_limit_buckets")
