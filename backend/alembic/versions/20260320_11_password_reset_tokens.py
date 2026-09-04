"""add password reset tokens table

Revision ID: 20260320_11
Revises: 20260320_10
Create Date: 2026-03-20 00:30:00
"""

from typing import Sequence, Union

from alembic import op

revision: str = "20260320_11"
down_revision: Union[str, Sequence[str], None] = "20260320_10"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS password_reset_tokens (
            id SERIAL PRIMARY KEY,
            user_id INTEGER NOT NULL REFERENCES users(id),
            code_hash VARCHAR(255) NOT NULL,
            expires_at TIMESTAMP NOT NULL,
            used_at TIMESTAMP NULL,
            created_at TIMESTAMP NOT NULL DEFAULT NOW()
        );
        """
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_password_reset_tokens_user_id ON password_reset_tokens(user_id);"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_password_reset_tokens_expires_at ON password_reset_tokens(expires_at);"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_password_reset_tokens_used_at ON password_reset_tokens(used_at);"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_password_reset_tokens_user_created ON password_reset_tokens(user_id, created_at);"
    )


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS password_reset_tokens;")
