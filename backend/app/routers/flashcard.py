"""
Flashcard CRUD and sync endpoints for the Flutter client.
"""

from __future__ import annotations

import uuid
from datetime import date, datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy.orm import Session

from .. import models
from ..database import get_db
from ..deps import require_user as _require_user

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
    flashcard_id: str
    grade: str
    reviewed_at: str | None = None


_GRADE_FACTOR = {"again": 0, "hard": 1, "good": 2, "easy": 3}


def _fsrs_simple(interval: int, easiness: float, grade_int: int) -> tuple[int, float]:
    if grade_int < 2:
        return 1, max(1.3, easiness - 0.2)
    new_ease = max(
        1.3, easiness + (0.1 - (3 - grade_int) * (0.08 + (3 - grade_int) * 0.02))
    )
    if interval <= 1:
        new_interval = 1 if grade_int == 2 else 4
    else:
        new_interval = round(interval * new_ease)
    return new_interval, new_ease


@router.post("/review")
def review_flashcard(
    body: FlashcardReviewIn,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = _require_user(authorization, db)
    card = (
        db.query(models.Flashcard)
        .filter(
            models.Flashcard.user_id == user.id,
            models.Flashcard.local_id == body.flashcard_id,
        )
        .first()
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
                .first()
            )
        except Exception:
            card = None
    if not card:
        raise HTTPException(status_code=404, detail="Flashcard não encontrado")

    grade_int = _GRADE_FACTOR.get((body.grade or "good").lower(), 2)
    new_interval, new_ease = _fsrs_simple(card.interval_days, card.easiness, grade_int)
    now = datetime.now(timezone.utc)
    card.interval_days = new_interval
    card.easiness = new_ease
    card.repetitions = int(card.repetitions or 0) + 1
    card.last_reviewed = now
    card.due_date = (now + timedelta(days=new_interval)).date()
    db.commit()
    db.refresh(card)
    return _card_to_dict(card)


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
