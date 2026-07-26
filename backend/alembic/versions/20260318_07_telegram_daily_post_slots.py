"""telegram daily post slots every 3h

Revision ID: 20260318_07
Revises: 20260313_06
Create Date: 2026-03-18 18:20:00.000000
"""

from alembic import op


# revision identifiers, used by Alembic.
revision = "20260318_07"
down_revision = "20260313_06"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        ALTER TABLE IF EXISTS telegram_daily_post_log
        ADD COLUMN IF NOT EXISTS slot_key VARCHAR(40);
        """
    )
    op.execute(
        """
        UPDATE telegram_daily_post_log
        SET slot_key = '08:00'
        WHERE COALESCE(slot_key, '') = '';
        """
    )
    op.execute(
        """
        ALTER TABLE IF EXISTS telegram_daily_post_log
        ALTER COLUMN slot_key SET DEFAULT '08:00';
        """
    )
    op.execute(
        """
        ALTER TABLE IF EXISTS telegram_daily_post_log
        ALTER COLUMN slot_key SET NOT NULL;
        """
    )
    op.execute(
        """
        ALTER TABLE IF EXISTS telegram_daily_post_log
        DROP CONSTRAINT IF EXISTS telegram_daily_post_log_day_key_key;
        """
    )
    op.execute("DROP INDEX IF EXISTS ix_telegram_daily_post_log_day_key;")
    op.execute(
        """
        CREATE INDEX IF NOT EXISTS ix_telegram_daily_post_log_day_key
        ON telegram_daily_post_log(day_key);
        """
    )
    op.execute(
        """
        CREATE UNIQUE INDEX IF NOT EXISTS uq_telegram_daily_post_log_day_slot
        ON telegram_daily_post_log(day_key, slot_key);
        """
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS uq_telegram_daily_post_log_day_slot;")
    op.execute(
        """
        ALTER TABLE IF EXISTS telegram_daily_post_log
        DROP COLUMN IF EXISTS slot_key;
        """
    )
    op.execute(
        """
        ALTER TABLE IF EXISTS telegram_daily_post_log
        ADD CONSTRAINT telegram_daily_post_log_day_key_key UNIQUE (day_key);
        """
    )
