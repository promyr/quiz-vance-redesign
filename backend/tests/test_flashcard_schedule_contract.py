from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from app import models
from app.routers import flashcard


@pytest.mark.parametrize(
    "grade,interval,ease,repetitions,expected",
    [
        ("again", 6, 2.5, 4, (1, 2.3, 0)),
        ("hard", 1, 2.5, 0, (1, 2.35, 1)),
        ("hard", 5, 1.31, 4, (6, 1.3, 5)),
        ("good", 3, 2.5, 0, (1, 2.5, 1)),
        ("good", 1, 2.5, 1, (6, 2.5, 2)),
        ("good", 6, 2.5, 2, (15, 2.5, 3)),
        ("good", 1, 2.5, 2, (3, 2.5, 3)),
        ("easy", 1, 2.5, 0, (4, 2.65, 1)),
        ("easy", 4, 2.5, 1, (14, 2.65, 2)),
        ("easy", 20, 3.9, 4, (104, 4.0, 5)),
        ("good", 100000, 4.0, 4, (36500, 4.0, 5)),
        ("again", 2, 5.0, 1, (1, 3.8, 0)),
    ],
)
def test_review_schedule_matches_mobile_contract(
    monkeypatch, grade, interval, ease, repetitions, expected
):
    engine = create_engine("sqlite+pysqlite:///:memory:")
    models.Base.metadata.create_all(engine)
    reviewed = datetime(2026, 1, 10, 12, tzinfo=timezone.utc)
    with Session(engine) as db:
        user = models.User(
            name="Student",
            login_id="student",
            email_id="student@test.invalid",
            password_hash="test-only",
        )
        db.add(user)
        db.flush()
        card = models.Flashcard(
            user_id=user.id,
            local_id="scheduled",
            front="Front",
            back="Back",
            due_date=reviewed.date(),
            interval_days=interval,
            easiness=ease,
            repetitions=repetitions,
        )
        db.add(card)
        db.commit()
        monkeypatch.setattr(flashcard, "_require_user", lambda *args: user)
        result = flashcard.review_flashcard(
            flashcard.FlashcardReviewIn(
                flashcard_id="scheduled", grade=grade, reviewed_at=reviewed.isoformat()
            ),
            "student",
            db,
        )
        assert result["interval_days"] == expected[0]
        assert result["easiness"] == pytest.approx(expected[1])
        assert result["repetitions"] == expected[2]
        assert (
            result["due_date"]
            == (reviewed + timedelta(days=expected[0])).date().isoformat()
        )
        assert result["xp_earned"] == 5
    engine.dispose()


def test_first_sync_of_previously_local_card_keeps_its_prior_schedule(monkeypatch):
    engine = create_engine("sqlite+pysqlite:///:memory:")
    models.Base.metadata.create_all(engine)
    with Session(engine) as db:
        user = models.User(
            name="Student",
            login_id="student",
            email_id="student@test.invalid",
            password_hash="test-only",
        )
        db.add(user)
        db.commit()
        monkeypatch.setattr(flashcard, "_require_user", lambda *args: user)
        body = flashcard.FlashcardReviewIn(
            flashcard_id="new-local",
            front="Front",
            back="Back",
            grade="good",
            interval_days=1,
            easiness=2.5,
            repetitions=1,
            reviewed_at=datetime.now(timezone.utc).isoformat(),
        )
        result = flashcard.review_flashcard(body, "student", db)
        assert result["interval_days"] == 6
        assert result["repetitions"] == 2
    engine.dispose()
