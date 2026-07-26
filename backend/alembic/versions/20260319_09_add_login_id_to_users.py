"""add login_id to users

Revision ID: 20260319_09
Revises: 20260319_08
Create Date: 2026-03-19 00:00:00
"""

from typing import Sequence, Union

from alembic import op

revision: str = "20260319_09"
down_revision: Union[str, Sequence[str], None] = "20260319_08"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS login_id VARCHAR(190);")
    op.execute(
        """
        UPDATE users
        SET login_id = LOWER(TRIM(email_id))
        WHERE COALESCE(TRIM(login_id), '') = '';
        """
    )
    op.execute("ALTER TABLE users ALTER COLUMN login_id SET NOT NULL;")
    op.execute("CREATE UNIQUE INDEX IF NOT EXISTS ix_users_login_id ON users(login_id);")
    op.execute(
        """
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1
                FROM pg_constraint
                WHERE conname = 'users_login_id_key'
            ) THEN
                ALTER TABLE users
                ADD CONSTRAINT users_login_id_key UNIQUE USING INDEX ix_users_login_id;
            END IF;
        END $$;
        """
    )


def downgrade() -> None:
    op.execute("ALTER TABLE users DROP CONSTRAINT IF EXISTS users_login_id_key;")
    op.execute("DROP INDEX IF EXISTS ix_users_login_id;")
    op.execute("ALTER TABLE users DROP COLUMN IF EXISTS login_id;")
