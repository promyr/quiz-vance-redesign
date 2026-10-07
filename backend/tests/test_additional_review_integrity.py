from datetime import datetime, timedelta, timezone

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine, func, select
from sqlalchemy.orm import Session

from app import models
from app.routers import flashcard, quiz


@pytest.fixture
def account(monkeypatch):
    engine = create_engine("sqlite+pysqlite:///:memory:")
    models.Base.metadata.create_all(engine)
    with Session(engine) as db:
        user = models.User(name="Test", login_id="test", email_id="test@invalid.local", password_hash="test-only")
        db.add(user)
        db.flush()
        card = models.Flashcard(user_id=user.id, local_id="card", front="Front", back="Back", due_date=datetime.now(timezone.utc).date())
        db.add(card)
        db.commit()
        monkeypatch.setattr(flashcard, "_require_user", lambda *args: user)
        monkeypatch.setattr(quiz, "_require_user", lambda *args: user)
        yield db, user, card
    engine.dispose()


def review(db, when, grade="good"):
    return flashcard.review_flashcard(flashcard.FlashcardReviewIn(flashcard_id="card", grade=grade, reviewed_at=when.isoformat()), "test", db)


def test_unique_offline_reviews_reordered_have_same_schedule_and_all_credits(account):
    db, user, card = account
    first = datetime.now(timezone.utc) - timedelta(days=3)
    results = [review(db, first + timedelta(days=offset)) for offset in (2, 0, 1)]
    db.refresh(user)
    assert [r["xp_earned"] for r in results] == [5, 5, 5]
    assert user.xp == 15
    assert results[-1]["repetitions"] == 3
    assert results[-1]["interval_days"] == 15
    assert db.scalar(select(func.count()).select_from(models.FlashcardReviewEvent)) == 3
    assert review(db, first)["xp_earned"] == 0
    assert card.repetitions == 3


def test_future_review_rejected_without_poisoning_current_review(account):
    db, _user, card = account
    now = datetime.now(timezone.utc)
    with pytest.raises(HTTPException) as error:
        review(db, now + timedelta(days=365))
    assert error.value.status_code == 422
    assert card.last_reviewed is None
    assert review(db, now)["xp_earned"] == 5


def test_stale_and_future_sync_do_not_overwrite_review_schedule(account):
    db, _user, card = account
    now = datetime.now(timezone.utc)
    review(db, now - timedelta(days=1))
    latest = review(db, now)
    item = flashcard.FlashcardSyncItem(local_id="card", front="Updated", back="Back", interval_days=1, repetitions=0, last_reviewed=(now-timedelta(days=2)).isoformat())
    flashcard.sync_flashcards(flashcard.FlashcardSyncIn(flashcards=[item]), 200, None, "test", db)
    db.refresh(card)
    assert card.front == "Updated"
    assert card.repetitions == latest["repetitions"] == 2
    assert card.interval_days == 6
    item.last_reviewed = (now+timedelta(days=365)).isoformat()
    with pytest.raises(HTTPException):
        flashcard.sync_flashcards(flashcard.FlashcardSyncIn(flashcards=[item]), 200, None, "test", db)
    assert card.interval_days == 6


def test_foreign_document_is_rejected_before_provider_or_quota(account, monkeypatch):
    db, _user, _card = account
    called = []
    monkeypatch.setattr(quiz, "_check_quiz_limit", lambda *args: called.append("quota"))
    monkeypatch.setattr(quiz, "_call_ai_for_user", lambda *args, **kwargs: called.append("provider"))
    other = models.User(name="Other", login_id="other", email_id="other@invalid.local", password_hash="test-only")
    db.add(other)
    db.flush()
    doc = models.StudyDocument(user_id=other.id, purpose="library", file_name="private.pdf", size_bytes=10, sha256="a"*64, status="ready", extracted_text="Private text")
    db.add(doc)
    db.commit()
    with pytest.raises(HTTPException) as error:
        quiz.generate_quiz(quiz.QuizGenerateIn(topic="Math", context="Manual excerpt", document_id=doc.id), "test", db)
    assert error.value.status_code == 404
    assert called == []


@pytest.mark.parametrize("order", [(0, 1, 2), (2, 0, 1), (1, 2, 0), (2, 1, 0)])
def test_mixed_grades_reconcile_in_event_order(account, order):
    db, _user, card = account
    start = datetime.now(timezone.utc) - timedelta(days=3)
    grades = ["easy", "again", "hard"]
    for index in order:
        review(db, start + timedelta(days=index), grades[index])
    assert card.repetitions == 1
    assert card.interval_days == 1
    assert card.easiness == pytest.approx(2.3)
    assert card.last_reviewed.replace(tzinfo=timezone.utc) == start + timedelta(days=2)
