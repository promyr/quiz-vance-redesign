"""add durable private PDF documents and background jobs

Revision ID: 20260729_20
Revises: 20260729_19
Create Date: 2026-07-29
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "20260729_20"
down_revision: str | Sequence[str] | None = "20260729_19"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "study_documents",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("purpose", sa.String(length=30), nullable=False),
        sa.Column("file_name", sa.String(length=255), nullable=False),
        sa.Column(
            "content_type",
            sa.String(length=80),
            server_default="application/pdf",
            nullable=False,
        ),
        sa.Column("size_bytes", sa.Integer(), nullable=False),
        sa.Column("sha256", sa.String(length=64), nullable=False),
        sa.Column("pdf_bytes", sa.LargeBinary(), nullable=False),
        sa.Column(
            "status",
            sa.String(length=40),
            server_default="uploading",
            nullable=False,
        ),
        sa.Column("progress", sa.Integer(), server_default="0", nullable=False),
        sa.Column("page_count", sa.Integer(), nullable=True),
        sa.Column(
            "cargos", sa.JSON(), server_default=sa.text("'[]'"), nullable=False
        ),
        sa.Column("exam_date", sa.String(length=10), nullable=True),
        sa.Column("selected_cargo_id", sa.String(length=120), nullable=True),
        sa.Column("selected_cargo_title", sa.String(length=255), nullable=True),
        sa.Column("extracted_text", sa.Text(), nullable=True),
        sa.Column("analysis_result", sa.JSON(), nullable=True),
        sa.Column("error_code", sa.String(length=80), nullable=True),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_study_documents_user_id", "study_documents", ["user_id"]
    )
    op.create_index(
        "ix_study_documents_purpose", "study_documents", ["purpose"]
    )
    op.create_index(
        "ix_study_documents_sha256", "study_documents", ["sha256"]
    )
    op.create_index(
        "ix_study_documents_status", "study_documents", ["status"]
    )
    op.create_index(
        "ix_study_documents_created_at", "study_documents", ["created_at"]
    )
    op.create_index(
        "ix_study_documents_user_status",
        "study_documents",
        ["user_id", "status"],
    )
    op.create_index(
        "ix_study_documents_user_created",
        "study_documents",
        ["user_id", "created_at"],
    )

    op.create_table(
        "study_document_pages",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("document_id", sa.Integer(), nullable=False),
        sa.Column("page_number", sa.Integer(), nullable=False),
        sa.Column("text", sa.Text(), nullable=False),
        sa.Column(
            "extraction_method",
            sa.String(length=20),
            server_default="native",
            nullable=False,
        ),
        sa.Column("quality", sa.Float(), server_default="0", nullable=False),
        sa.Column("text_sha256", sa.String(length=64), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["document_id"], ["study_documents.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "document_id", "page_number", name="uq_study_document_page"
        ),
    )
    op.create_index(
        "ix_study_document_pages_document_id",
        "study_document_pages",
        ["document_id"],
    )
    op.create_index(
        "ix_study_document_pages_document_page",
        "study_document_pages",
        ["document_id", "page_number"],
    )

    op.create_table(
        "study_document_jobs",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("document_id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("kind", sa.String(length=30), nullable=False),
        sa.Column(
            "status",
            sa.String(length=30),
            server_default="queued",
            nullable=False,
        ),
        sa.Column("progress", sa.Integer(), server_default="0", nullable=False),
        sa.Column(
            "attempt_count", sa.Integer(), server_default="0", nullable=False
        ),
        sa.Column("max_attempts", sa.Integer(), server_default="3", nullable=False),
        sa.Column("payload", sa.JSON(), nullable=True),
        sa.Column("result", sa.JSON(), nullable=True),
        sa.Column(
            "available_at",
            sa.DateTime(),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column("locked_by", sa.String(length=120), nullable=True),
        sa.Column("locked_until", sa.DateTime(), nullable=True),
        sa.Column("error_code", sa.String(length=80), nullable=True),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["document_id"], ["study_documents.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_study_document_jobs_document_id",
        "study_document_jobs",
        ["document_id"],
    )
    op.create_index(
        "ix_study_document_jobs_user_id", "study_document_jobs", ["user_id"]
    )
    op.create_index(
        "ix_study_document_jobs_kind", "study_document_jobs", ["kind"]
    )
    op.create_index(
        "ix_study_document_jobs_status", "study_document_jobs", ["status"]
    )
    op.create_index(
        "ix_study_document_jobs_available_at",
        "study_document_jobs",
        ["available_at"],
    )
    op.create_index(
        "ix_study_document_jobs_locked_until",
        "study_document_jobs",
        ["locked_until"],
    )
    op.create_index(
        "ix_study_document_jobs_created_at",
        "study_document_jobs",
        ["created_at"],
    )
    op.create_index(
        "ix_study_document_jobs_queue",
        "study_document_jobs",
        ["status", "available_at", "locked_until"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_study_document_jobs_queue", table_name="study_document_jobs"
    )
    op.drop_index(
        "ix_study_document_jobs_created_at",
        table_name="study_document_jobs",
    )
    op.drop_index(
        "ix_study_document_jobs_locked_until",
        table_name="study_document_jobs",
    )
    op.drop_index(
        "ix_study_document_jobs_available_at",
        table_name="study_document_jobs",
    )
    op.drop_index(
        "ix_study_document_jobs_status", table_name="study_document_jobs"
    )
    op.drop_index(
        "ix_study_document_jobs_kind", table_name="study_document_jobs"
    )
    op.drop_index(
        "ix_study_document_jobs_user_id", table_name="study_document_jobs"
    )
    op.drop_index(
        "ix_study_document_jobs_document_id",
        table_name="study_document_jobs",
    )
    op.drop_table("study_document_jobs")

    op.drop_index(
        "ix_study_document_pages_document_page",
        table_name="study_document_pages",
    )
    op.drop_index(
        "ix_study_document_pages_document_id",
        table_name="study_document_pages",
    )
    op.drop_table("study_document_pages")

    op.drop_index(
        "ix_study_documents_user_created", table_name="study_documents"
    )
    op.drop_index(
        "ix_study_documents_user_status", table_name="study_documents"
    )
    op.drop_index(
        "ix_study_documents_created_at", table_name="study_documents"
    )
    op.drop_index(
        "ix_study_documents_status", table_name="study_documents"
    )
    op.drop_index(
        "ix_study_documents_sha256", table_name="study_documents"
    )
    op.drop_index(
        "ix_study_documents_purpose", table_name="study_documents"
    )
    op.drop_index(
        "ix_study_documents_user_id", table_name="study_documents"
    )
    op.drop_table("study_documents")
