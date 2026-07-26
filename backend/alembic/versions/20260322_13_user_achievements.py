"""user_achievements table

Revision ID: 20260322_13
Revises: 20260322_12
Create Date: 2026-03-22
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa

revision = "20260322_13"
down_revision = "20260322_12"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "user_achievements",
        sa.Column("id", sa.Integer, primary_key=True, autoincrement=True),
        sa.Column("user_id", sa.Integer, sa.ForeignKey("users.id"), nullable=False),
        sa.Column("achievement_id", sa.String(80), nullable=False),
        sa.Column("title", sa.String(120), nullable=False),
        sa.Column("description", sa.Text, nullable=True),
        sa.Column("icon", sa.String(10), nullable=True),
        sa.Column("xp_reward", sa.Integer, nullable=False, server_default="0"),
        sa.Column("notified", sa.Integer, nullable=False, server_default="0"),
        sa.Column(
            "unlocked_at",
            sa.DateTime,
            nullable=False,
            server_default=sa.func.now(),
        ),
    )
    op.create_index("ix_user_achievements_user_id", "user_achievements", ["user_id"])
    op.create_index("ix_user_achievements_unlocked_at", "user_achievements", ["unlocked_at"])
    op.create_index(
        "ix_user_achievements_user_notified",
        "user_achievements",
        ["user_id", "notified"],
    )
    op.create_unique_constraint(
        "uq_user_achievement",
        "user_achievements",
        ["user_id", "achievement_id"],
    )


def downgrade() -> None:
    op.drop_table("user_achievements")
