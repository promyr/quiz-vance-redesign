"""add secure admin role, master AI keys and audit trail

Revision ID: 20260725_17
Revises: 20260330_16
Create Date: 2026-07-25
"""

from typing import Sequence, Union

from alembic import op


revision: str = "20260725_17"
down_revision: Union[str, Sequence[str], None] = "20260330_16"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS role VARCHAR(20) NOT NULL DEFAULT 'user';"
    )
    op.execute("CREATE INDEX IF NOT EXISTS ix_users_role ON users(role);")
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS ai_master_keys (
            id SERIAL PRIMARY KEY,
            provider VARCHAR(30) NOT NULL,
            label VARCHAR(120) NOT NULL,
            secret_encrypted TEXT NOT NULL,
            key_suffix VARCHAR(8) NOT NULL,
            priority INTEGER NOT NULL DEFAULT 100,
            is_active INTEGER NOT NULL DEFAULT 1,
            health_status VARCHAR(30) NOT NULL DEFAULT 'unknown',
            failure_count INTEGER NOT NULL DEFAULT 0,
            blocked_until TIMESTAMP NULL,
            last_tested_at TIMESTAMP NULL,
            last_success_at TIMESTAMP NULL,
            last_error_code VARCHAR(50) NULL,
            created_by_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
            created_at TIMESTAMP NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMP NOT NULL DEFAULT NOW()
        );
        """
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_ai_master_keys_provider "
        "ON ai_master_keys(provider);"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_ai_master_keys_routing "
        "ON ai_master_keys(provider, is_active, priority, blocked_until);"
    )
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS admin_audit_events (
            id SERIAL PRIMARY KEY,
            actor_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
            action VARCHAR(80) NOT NULL,
            target_type VARCHAR(50) NOT NULL,
            target_id VARCHAR(80) NULL,
            result VARCHAR(30) NOT NULL DEFAULT 'success',
            source_ip VARCHAR(64) NULL,
            details_json TEXT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT NOW()
        );
        """
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_admin_audit_events_actor "
        "ON admin_audit_events(actor_user_id);"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_admin_audit_events_created "
        "ON admin_audit_events(created_at);"
    )


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS admin_audit_events;")
    op.execute("DROP TABLE IF EXISTS ai_master_keys;")
    op.execute("DROP INDEX IF EXISTS ix_users_role;")
    op.execute("ALTER TABLE users DROP COLUMN IF EXISTS role;")
