"""add device-bound biometric step-up for admin actions

Revision ID: 20260729_19
Revises: 20260725_18
Create Date: 2026-07-29
"""

from collections.abc import Sequence

from alembic import op

revision: str = "20260729_19"
down_revision: str | Sequence[str] | None = "20260725_18"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS admin_biometric_credentials (
            id SERIAL PRIMARY KEY,
            credential_id VARCHAR(120) NOT NULL UNIQUE,
            user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            public_key VARCHAR(64) NOT NULL,
            device_name VARCHAR(120) NOT NULL,
            platform VARCHAR(30) NOT NULL,
            enrolled_auth_version INTEGER NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1,
            last_used_at TIMESTAMP NULL,
            created_at TIMESTAMP NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMP NOT NULL DEFAULT NOW()
        );
        """
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_admin_biometric_credentials_user "
        "ON admin_biometric_credentials(user_id);"
    )
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS admin_biometric_challenges (
            id SERIAL PRIMARY KEY,
            challenge_id VARCHAR(80) NOT NULL UNIQUE,
            credential_id INTEGER NOT NULL
                REFERENCES admin_biometric_credentials(id) ON DELETE CASCADE,
            user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            scope VARCHAR(80) NOT NULL,
            challenge TEXT NOT NULL,
            expires_at TIMESTAMP NOT NULL,
            used_at TIMESTAMP NULL,
            created_at TIMESTAMP NOT NULL DEFAULT NOW()
        );
        """
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_admin_biometric_challenges_expires "
        "ON admin_biometric_challenges(expires_at);"
    )
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS admin_step_up_grants (
            id SERIAL PRIMARY KEY,
            token_hash VARCHAR(64) NOT NULL UNIQUE,
            user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            credential_id INTEGER NOT NULL
                REFERENCES admin_biometric_credentials(id) ON DELETE CASCADE,
            scope VARCHAR(80) NOT NULL,
            expires_at TIMESTAMP NOT NULL,
            used_at TIMESTAMP NULL,
            created_at TIMESTAMP NOT NULL DEFAULT NOW()
        );
        """
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_admin_step_up_grants_expires "
        "ON admin_step_up_grants(expires_at);"
    )


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS admin_step_up_grants;")
    op.execute("DROP TABLE IF EXISTS admin_biometric_challenges;")
    op.execute("DROP TABLE IF EXISTS admin_biometric_credentials;")
