"""usage_daily composite index for weekly quota queries

Revision ID: 20260328_14
Revises: 20260322_13
Create Date: 2026-03-28

Adiciona índice composto (user_id, feature_key, day_key) na tabela usage_daily.
Melhora a performance das queries de quota semanal que filtram por
user_id + feature_key + day_key >= week_start.
"""

from __future__ import annotations

from alembic import op

revision = "20260328_14"
down_revision = "20260322_13"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_index(
        "ix_usage_daily_user_feature_day",
        "usage_daily",
        ["user_id", "feature_key", "day_key"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_usage_daily_user_feature_day", table_name="usage_daily")
