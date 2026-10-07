import importlib.util
from pathlib import Path
from types import SimpleNamespace

from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.dialects import postgresql

from app import models
from app.quiz_scoring import increment_daily


def test_reward_tables_upgrade_and_downgrade_preserve_existing_accounts(tmp_path):
    engine = create_engine(f"sqlite+pysqlite:///{tmp_path / 'migration.sqlite'}")
    excluded = {"quiz_answer_credits", "flashcard_review_events"}
    models.Base.metadata.create_all(
        engine,
        tables=[
            table
            for table in models.Base.metadata.sorted_tables
            if table.name not in excluded
        ],
    )
    migration_file = (
        Path(__file__).parents[1]
        / "alembic/versions/20261006_22_flashcard_review_rewards.py"
    )
    spec = importlib.util.spec_from_file_location(
        "learning_rewards_migration", migration_file
    )
    migration = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(migration)
    with engine.begin() as connection:
        connection.execute(
            models.User.__table__.insert().values(
                name="Test",
                login_id="test",
                email_id="test@invalid.local",
                password_hash="test-only",
                xp=17,
            )
        )
        context = MigrationContext.configure(connection)
        with Operations.context(context):
            migration.upgrade()
            assert excluded <= set(inspect(connection).get_table_names())
            migration.downgrade()
        assert not excluded & set(inspect(connection).get_table_names())
        assert connection.execute(text("SELECT xp FROM users")).scalar_one() == 17
    engine.dispose()


def test_postgresql_daily_increment_compiles_as_atomic_upsert():
    class Database:
        statement = None

        def get_bind(self):
            return SimpleNamespace(dialect=SimpleNamespace(name="postgresql"))

        def execute(self, statement):
            self.statement = statement

    db = Database()
    increment_daily(db, 4, total=2, correct=1, xp=10)
    sql = str(db.statement.compile(dialect=postgresql.dialect()))
    assert "ON CONFLICT (user_id, day_key) DO UPDATE" in sql
    assert "coalesce(quiz_stats_daily.questoes" in sql
    assert "coalesce(quiz_stats_daily.acertos" in sql
    assert "coalesce(quiz_stats_daily.xp_ganho" in sql
