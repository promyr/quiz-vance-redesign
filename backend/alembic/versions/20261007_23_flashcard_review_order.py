"""Retain review grades to reconcile offline events chronologically."""
import sqlalchemy as sa

from alembic import op

revision = "20261007_23"
down_revision = "20261006_22"
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table("flashcard_review_events") as batch:
        batch.add_column(sa.Column("flashcard_id", sa.Integer(), nullable=True))
        batch.add_column(sa.Column("grade", sa.String(12), nullable=True))
        batch.add_column(sa.Column("initial_schedule", sa.JSON(), nullable=True))
        batch.create_foreign_key("fk_review_event_flashcard", "flashcards", ["flashcard_id"], ["id"], ondelete="CASCADE")
        batch.create_index("ix_flashcard_review_events_flashcard_id", ["flashcard_id"])


def downgrade():
    with op.batch_alter_table("flashcard_review_events") as batch:
        batch.drop_index("ix_flashcard_review_events_flashcard_id")
        batch.drop_constraint("fk_review_event_flashcard", type_="foreignkey")
        batch.drop_column("initial_schedule")
        batch.drop_column("grade")
        batch.drop_column("flashcard_id")
