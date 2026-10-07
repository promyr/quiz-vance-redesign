"""Idempotent flashcard review rewards.

Revision ID: 20261006_22
Revises: 20260729_21
"""

import sqlalchemy as sa

from alembic import op

revision = "20261006_22"
down_revision = "20260729_21"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "quiz_answer_credits",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("question_key", sa.String(64), nullable=False),
        sa.Column("event_id", sa.String(120), nullable=False),
        sa.UniqueConstraint(
            "user_id", "question_key", name="uq_quiz_answer_credit_user_question"
        ),
    )
    op.create_index(
        "ix_quiz_answer_credits_user_id", "quiz_answer_credits", ["user_id"]
    )
    op.create_table(
        "flashcard_review_events",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("event_key", sa.String(64), nullable=False),
        sa.Column("reviewed_at", sa.DateTime(), nullable=False),
        sa.Column("xp_delta", sa.Integer(), nullable=False),
        sa.UniqueConstraint(
            "user_id", "event_key", name="uq_flashcard_review_user_event"
        ),
    )
    op.create_index(
        "ix_flashcard_review_events_user_id", "flashcard_review_events", ["user_id"]
    )
    op.create_index(
        "ix_flashcard_review_events_reviewed_at",
        "flashcard_review_events",
        ["reviewed_at"],
    )


def downgrade():
    op.drop_table("flashcard_review_events")
    op.drop_table("quiz_answer_credits")
