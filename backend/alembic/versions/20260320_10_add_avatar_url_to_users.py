"""add avatar_url to users

Revision ID: 20260320_10
Revises: 20260319_09
Create Date: 2026-03-20 00:00:00
"""

from typing import Sequence, Union

from alembic import op

revision: str = "20260320_10"
down_revision: Union[str, Sequence[str], None] = "20260319_09"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_url TEXT;")


def downgrade() -> None:
    op.execute("ALTER TABLE users DROP COLUMN IF EXISTS avatar_url;")
