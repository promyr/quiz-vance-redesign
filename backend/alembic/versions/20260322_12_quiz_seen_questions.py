"""add quiz_seen_questions table

Revision ID: 20260322_12
Revises: 20260320_11
Create Date: 2026-03-22 00:00:00
"""

from typing import Sequence, Union

from alembic import op

revision: str = "20260322_12"
down_revision: Union[str, Sequence[str], None] = "20260320_11"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS quiz_seen_questions (
            id         SERIAL PRIMARY KEY,
            user_id    INTEGER NOT NULL REFERENCES users(id),
            topic_key  VARCHAR(200) NOT NULL,
            fingerprint VARCHAR(16) NOT NULL,
            question_text TEXT NOT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT NOW(),
            CONSTRAINT uq_quiz_seen_question_user_fp UNIQUE (user_id, fingerprint)
        );
        """
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_quiz_seen_user_topic_created "
        "ON quiz_seen_questions(user_id, topic_key, created_at);"
    )


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS quiz_seen_questions;")
