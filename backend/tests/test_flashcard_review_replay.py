from datetime import datetime, timedelta, timezone

from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from app import models
from app.routers import flashcard


def test_duplicate_and_older_reviews_do_not_advance_card_twice(monkeypatch):
    engine = create_engine('sqlite+pysqlite:///:memory:')
    models.Base.metadata.create_all(engine)
    with Session(engine) as db:
        user = models.User(name='Test', login_id='test', email_id='test@invalid.local', password_hash='test-only')
        db.add(user)
        db.flush()
        card = models.Flashcard(user_id=user.id, local_id='card', front='Front', back='Back', due_date=datetime.now(timezone.utc).date())
        db.add(card)
        db.commit()
        monkeypatch.setattr(flashcard, '_require_user', lambda *args: user)
        reviewed = datetime.now(timezone.utc) - timedelta(minutes=1)
        body = flashcard.FlashcardReviewIn(flashcard_id='card', grade='good', reviewed_at=reviewed.isoformat())
        flashcard.review_flashcard(body, authorization='test', db=db)
        flashcard.review_flashcard(body, authorization='test', db=db)
        older = flashcard.FlashcardReviewIn(flashcard_id='card', grade='again', reviewed_at=(reviewed-timedelta(days=1)).isoformat())
        flashcard.review_flashcard(older, authorization='test', db=db)
        db.refresh(card)
        assert card.repetitions == 1
