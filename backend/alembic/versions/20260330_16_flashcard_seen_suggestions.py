"""add flashcard_seen_suggestions table

Revision ID: 20260330_16
Revises: 20260328_15
Create Date: 2026-03-30 00:00:00

Cria a tabela flashcard_seen_suggestions para rastrear flashcards já
gerados por usuário/tópico, evitando repetição nas gerações seguintes.
"""

from typing import Sequence, Union

from alembic import op

revision: str = "20260330_16"
down_revision: Union[str, Sequence[str], None] = "20260328_15"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS flashcard_seen_suggestions (
            id          SERIAL PRIMARY KEY,
            user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            topic_key   VARCHAR(120) NOT NULL,
            fingerprint VARCHAR(16)  NOT NULL,
            front_text  VARCHAR(200) NOT NULL,
            created_at  TIMESTAMP NOT NULL DEFAULT NOW(),
            CONSTRAINT uq_flashcard_seen_user_fp UNIQUE (user_id, fingerprint)
        );
        """
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_flashcard_seen_user_topic "
        "ON flashcard_seen_suggestions(user_id, topic_key);"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_flashcard_seen_user_topic_created "
        "ON flashcard_seen_suggestions(user_id, topic_key, created_at);"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_flashcard_seen_user_topic_created;")
    op.execute("DROP INDEX IF EXISTS ix_flashcard_seen_user_topic;")
    op.execute("DROP TABLE IF EXISTS flashcard_seen_suggestions;")
