"""
Flashcard CRUD and sync endpoints for the Flutter client.
"""

from __future__ import annotations

import hashlib
import math
import uuid
from datetime import date, datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlalchemy.orm import Session

from .. import models
from ..database import get_db
from ..deps import require_user as _require_user
from ..quiz_scoring import conflict_insert

router = APIRouter(prefix="/flashcards", tags=["flashcards"])


def _card_to_dict(card: models.Flashcard) -> dict:
    return {
        "id": card.local_id,
        "remote_id": str(card.id),
        "front": card.front,
        "back": card.back,
        "topic": card.topic,
        "interval_days": card.interval_days,
        "easiness": float(card.easiness or 2.5),
        "due_date": card.due_date.isoformat() if card.due_date else None,
        "repetitions": card.repetitions,
        "last_reviewed": card.last_reviewed.isoformat() if card.last_reviewed else None,
        "synced": True,
        "created_at": card.created_at.isoformat() if card.created_at else None,
    }


@router.get("")
def get_due_flashcards(
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = _require_user(authorization, db)
    today = datetime.now(timezone.utc).date()
    cards = (
        db.query(models.Flashcard)
        .filter(
            models.Flashcard.user_id == user.id,
            models.Flashcard.due_date <= today,
        )
        .order_by(models.Flashcard.due_date.asc())
        .limit(200)
        .all()
    )
    return {"flashcards": [_card_to_dict(card) for card in cards]}


class FlashcardCreateIn(BaseModel):
    front: str
    back: str
    topic: str | None = None
    local_id: str | None = None


@router.post("/create")
def create_flashcard(
    body: FlashcardCreateIn,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = _require_user(authorization, db)
    card = models.Flashcard(
        user_id=user.id,
        local_id=body.local_id or str(uuid.uuid4()),
        front=(body.front or "").strip(),
        back=(body.back or "").strip(),
        topic=body.topic,
        interval_days=1,
        easiness=2.5,
        due_date=datetime.now(timezone.utc).date(),
        repetitions=0,
        created_at=datetime.now(timezone.utc),
    )
    db.add(card)
    db.commit()
    db.refresh(card)
    return _card_to_dict(card)


class FlashcardReviewIn(BaseModel):
    flashcard_id: str = Field(min_length=1, max_length=64)
    grade: str
    reviewed_at: str | None = None
    front: str | None = Field(default=None, max_length=20000)
    back: str | None = Field(default=None, max_length=20000)
    topic: str | None = Field(default=None, max_length=120)
    interval_days: int = Field(default=1, ge=1, le=36500)
    easiness: float = Field(default=2.5, ge=1.3, le=4.0)
    repetitions: int = Field(default=0, ge=0, le=100000)


_GRADE_FACTOR = {"again": 0, "hard": 1, "good": 2, "easy": 3}


def _schedule_review(interval: int, easiness: float, repetitions: int, grade_int: int) -> tuple[int, float, int]:
    """Same contract as mobile spaced_repetition.scheduleFlashcardReview.

    Dart rounds positive ties up; Python's built-in round uses banker's rounding.
    """
    ease = max(1.3, min(4.0, easiness))
    if grade_int == 0:
        reps, ease, interval = 0, max(1.3, ease - 0.2), 1
    elif grade_int == 1:
        reps, ease = repetitions + 1, max(1.3, ease - 0.15)
        interval = max(1, math.floor(interval * 1.2 + 0.5))
    elif grade_int == 2:
        reps = repetitions + 1
        interval = 1 if reps == 1 else 6 if reps == 2 else math.floor(interval * ease + 0.5)
    else:
        reps, ease = repetitions + 1, min(4.0, ease + 0.15)
        interval = 4 if reps == 1 else math.floor(interval * ease * 1.3 + 0.5)
    return max(1, min(36500, interval)), ease, reps


@router.post("/review")
def review_flashcard(
    body: FlashcardReviewIn,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = _require_user(authorization, db)
    # A harmless write serializes reviews for this account on SQLite as well as
    # PostgreSQL; the earlier user read must never overwrite the XP column.
    db.execute(text("UPDATE users SET xp = COALESCE(xp, 0) WHERE id = :uid"), {"uid": user.id})
    card = (
        db.query(models.Flashcard)
        .filter(
            models.Flashcard.user_id == user.id,
            models.Flashcard.local_id == body.flashcard_id,
        )
        .with_for_update().first()
    )
    if not card:
        try:
            remote_id = int(body.flashcard_id)
            card = (
                db.query(models.Flashcard)
                .filter(
                    models.Flashcard.user_id == user.id,
                    models.Flashcard.id == remote_id,
                )
                .with_for_update().first()
            )
        except Exception:
            card = None
    if not card and (body.front or '').strip() and (body.back or '').strip():
        card = models.Flashcard(user_id=user.id, local_id=body.flashcard_id,
            front=body.front.strip(), back=body.back.strip(), topic=body.topic,
            due_date=datetime.now(timezone.utc).date(), interval_days=body.interval_days,
            easiness=body.easiness, repetitions=body.repetitions)
        db.add(card)
        db.flush()
    if not card:
        raise HTTPException(status_code=404, detail="Flashcard não encontrado")

    # reviewed_at is an event version: replayed/older offline reviews must
    # not advance the schedule again. Row locks serialize production writes.
    reviewed_at = None
    if body.reviewed_at:
        try:
            reviewed_at = datetime.fromisoformat(body.reviewed_at.replace("Z", "+00:00"))
            if reviewed_at.tzinfo is None:
                reviewed_at = reviewed_at.replace(tzinfo=timezone.utc)
            reviewed_at = reviewed_at.astimezone(timezone.utc)
        except ValueError:
            raise HTTPException(status_code=422, detail="Data de revisao invalida.") from None
        if card.last_reviewed:
            last = card.last_reviewed
            if last.tzinfo is None:
                last = last.replace(tzinfo=timezone.utc)
            if reviewed_at <= last:
                db.commit()
                return {**_card_to_dict(card), 'xp_earned': 0}

    grade_int = _GRADE_FACTOR.get((body.grade or "good").lower(), 2)
    new_interval, new_ease, new_repetitions = _schedule_review(card.interval_days, card.easiness, card.repetitions, grade_int)
    now = datetime.now(timezone.utc)
    card.interval_days = new_interval
    card.easiness = new_ease
    card.repetitions = new_repetitions
    card.last_reviewed = reviewed_at or now
    card.due_date = (card.last_reviewed + timedelta(days=new_interval)).date()
    event_key = hashlib.sha256(f'{card.id}:{card.last_reviewed.isoformat()}'.encode()).hexdigest()
    inserted = db.execute(conflict_insert(db, models.FlashcardReviewEvent).values(
        user_id=user.id, event_key=event_key, reviewed_at=card.last_reviewed, xp_delta=5
    ).on_conflict_do_nothing(index_elements=['user_id', 'event_key']))
    earned = 5 if inserted.rowcount == 1 else 0
    if earned:
        db.execute(text("UPDATE users SET xp = COALESCE(xp, 0) + :delta WHERE id = :uid"), {'delta': earned, 'uid': user.id})
    db.commit()
    db.refresh(card)
    return {**_card_to_dict(card), 'xp_earned': earned}


class FlashcardSyncItem(BaseModel):
    local_id: str
    front: str
    back: str
    topic: str | None = None
    interval_days: int = 1
    easiness: float = 2.5
    due_date: str | None = None
    repetitions: int = 0
    last_reviewed: str | None = None
    created_at: str | None = None


class FlashcardSyncIn(BaseModel):
    flashcards: list[FlashcardSyncItem] = []


def _parse_sync_date(value: str | None) -> date | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).date()
    except Exception:
        try:
            return date.fromisoformat(value[:10])
        except Exception:
            return None


def _parse_sync_dt(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except Exception:
        return None


@router.post("/sync")
def sync_flashcards(
    body: FlashcardSyncIn,
    limit: int = Query(default=200, ge=1, le=500),
    cursor: int | None = Query(default=None, ge=0),
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = _require_user(authorization, db)
    valid_items = [
        item
        for item in body.flashcards[:500]
        if (item.front or "").strip() and (item.back or "").strip()
    ]

    if not valid_items:
        return _paginated_sync_response(
            db, user.id, synced=0, limit=limit, cursor=cursor
        )

    incoming_ids = [item.local_id for item in valid_items]
    existing_map: dict[str, models.Flashcard] = {
        card.local_id: card
        for card in db.query(models.Flashcard)
        .filter(
            models.Flashcard.user_id == user.id,
            models.Flashcard.local_id.in_(incoming_ids),
        )
        .all()
    }

    synced = 0
    for item in valid_items:
        due = _parse_sync_date(item.due_date) or datetime.now(timezone.utc).date()
        last_reviewed = _parse_sync_dt(item.last_reviewed)
        created_at = _parse_sync_dt(item.created_at) or datetime.now(timezone.utc)

        existing = existing_map.get(item.local_id)
        if existing:
            existing.front = item.front
            existing.back = item.back
            existing.topic = item.topic
            existing.interval_days = item.interval_days
            existing.easiness = item.easiness
            existing.due_date = due
            existing.repetitions = item.repetitions
            existing.last_reviewed = last_reviewed
        else:
            db.add(
                models.Flashcard(
                    user_id=user.id,
                    local_id=item.local_id,
                    front=item.front,
                    back=item.back,
                    topic=item.topic,
                    interval_days=item.interval_days,
                    easiness=item.easiness,
                    due_date=due,
                    repetitions=item.repetitions,
                    last_reviewed=last_reviewed,
                    created_at=created_at,
                )
            )
        synced += 1

    db.commit()
    return _paginated_sync_response(
        db, user.id, synced=synced, limit=limit, cursor=cursor
    )


def _paginated_sync_response(
    db: Session,
    user_id: int,
    *,
    synced: int,
    limit: int,
    cursor: int | None,
) -> dict:
    query = db.query(models.Flashcard).filter(models.Flashcard.user_id == user_id)
    if cursor:
        query = query.filter(models.Flashcard.id > int(cursor))

    rows = query.order_by(models.Flashcard.id.asc()).limit(limit + 1).all()
    has_more = len(rows) > limit
    page_rows = rows[:limit]
    next_cursor = int(page_rows[-1].id) if has_more and page_rows else None
    return {
        "synced": synced,
        "flashcards": [_card_to_dict(card) for card in page_rows],
        "has_more": has_more,
        "next_cursor": next_cursor,
    }
