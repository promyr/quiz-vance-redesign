import importlib.util
from pathlib import Path

from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy import create_engine, inspect, text

from app import models


def test_review_order_migration_preserves_legacy_events_and_rewards(tmp_path):
    engine = create_engine(f"sqlite+pysqlite:///{tmp_path / 'reviews.sqlite'}")
    models.Base.metadata.create_all(engine)
    path = Path(__file__).parents[1] / "alembic/versions/20261007_23_flashcard_review_order.py"
    spec = importlib.util.spec_from_file_location("review_order_migration", path)
    migration = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(migration)
    with engine.begin() as connection:
        connection.execute(models.User.__table__.insert().values(name="Legacy", login_id="legacy", email_id="legacy@test.invalid", password_hash="test-only", xp=35))
        context = MigrationContext.configure(connection)
        with Operations.context(context):
            migration.downgrade()
            connection.execute(text("INSERT INTO flashcard_review_events (user_id,event_key,reviewed_at,xp_delta) VALUES (1,'legacy-event','2026-01-01 00:00:00',5)"))
            migration.upgrade()
            assert {"flashcard_id", "grade", "initial_schedule"} <= {column["name"] for column in inspect(connection).get_columns("flashcard_review_events")}
            assert connection.execute(text("SELECT event_key, xp_delta, grade FROM flashcard_review_events")).one() == ("legacy-event", 5, None)
            assert connection.execute(text("SELECT xp FROM users")).scalar_one() == 35
            migration.downgrade()
            assert connection.execute(text("SELECT event_key FROM flashcard_review_events")).scalar_one() == "legacy-event"
    engine.dispose()
