"""flashcards table

Revision ID: 20260319_08
Revises: 20260318_07
Create Date: 2026-03-19 00:00:00
"""

from typing import Sequence, Union
from alembic import op

revision: str = "20260319_08"
down_revision: Union[str, Sequence[str], None] = "20260318_07"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("""
        CREATE TABLE IF NOT EXISTS flashcards (
            id          BIGSERIAL PRIMARY KEY,
            user_id     BIGINT NOT NULL REFERENCES users(id),
            local_id    VARCHAR(64) NOT NULL,
            front       TEXT NOT NULL,
            back        TEXT NOT NULL,
            topic       VARCHAR(120),
            interval_days INTEGER DEFAULT 1,
            easiness    FLOAT DEFAULT 2.5,
            due_date    DATE NOT NULL,
            repetitions INTEGER DEFAULT 0,
            last_reviewed TIMESTAMP,
            created_at  TIMESTAMP DEFAULT NOW(),
            CONSTRAINT uq_flashcard_user_local UNIQUE (user_id, local_id)
        );
    """)
    op.execute("CREATE INDEX IF NOT EXISTS ix_flashcards_user_due ON flashcards(user_id, due_date);")


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_flashcards_user_due;")
    op.execute("DROP TABLE IF EXISTS flashcards;")
