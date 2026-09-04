"""move private PDFs out of PostgreSQL

Revision ID: 20260729_21
Revises: 20260729_20
Create Date: 2026-07-29
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "20260729_21"
down_revision: str | Sequence[str] | None = "20260729_20"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    with op.batch_alter_table("study_documents") as batch:
        batch.add_column(
            sa.Column("storage_key", sa.String(length=500), nullable=True)
        )
        batch.alter_column(
            "pdf_bytes",
            existing_type=sa.LargeBinary(),
            nullable=True,
        )


def downgrade() -> None:
    # A coluna binaria permanece anulavel para que um rollback do codigo nao
    # destrua documentos que ja estejam no volume privado.
    with op.batch_alter_table("study_documents") as batch:
        batch.drop_column("storage_key")
