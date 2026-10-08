"""Account-bound answer receipts and atomic daily aggregates.

Receipts travel in question IDs so old question serializers retain them offline.
Only the server chooses the scoring rule and signed answer key.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import uuid
from datetime import datetime, timezone

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert

from . import models


def _key() -> bytes:
    secret = os.getenv("APP_BACKEND_SECRET", "").strip()
    if not secret:
        raise RuntimeError("app_secret_missing")
    return hashlib.sha256(("quiz-answer-receipt:v1:" + secret).encode()).digest()


def signed_questions(questions: list[dict], user_id: int, feature: str) -> list[dict]:
    result = []
    for question in questions:
        payload = {
            "u": user_id,
            "f": feature,
            "n": uuid.uuid4().hex,
            "c": str(question.get("correct_option_id") or question["correctOptionId"]),
            "o": [str(option["id"]) for option in question["options"]],
        }
        raw = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()
        body = base64.urlsafe_b64encode(raw).decode().rstrip("=")
        signature = hmac.new(_key(), body.encode(), hashlib.sha256).hexdigest()
        result.append({**question, "id": f"qv1.{body}.{signature}"})
    return result


def score_answers(answers: list, total: int, user_id: int, feature: str) -> int:
    if len(answers) != total:
        raise HTTPException(
            422, "Envie as respostas de todas as questões para validar o resultado."
        )
    correct = 0
    seen = set()
    for answer in answers:
        try:
            prefix, body, signature = answer.question_id.split(".")
            expected = hmac.new(_key(), body.encode(), hashlib.sha256).hexdigest()
            if prefix != "qv1" or not hmac.compare_digest(signature, expected):
                raise ValueError()
            payload = json.loads(
                base64.urlsafe_b64decode(body + "=" * (-len(body) % 4))
            )
            if (
                payload["u"] != user_id
                or payload["f"] != feature
                or answer.question_id in seen
            ):
                raise ValueError()
            selected = answer.selected_option_id
            if selected is not None and selected not in payload["o"]:
                raise ValueError()
            seen.add(answer.question_id)
            correct += int(selected is not None and selected == payload["c"])
        except (ValueError, TypeError, KeyError, UnicodeDecodeError):
            raise HTTPException(
                422,
                "Esta questão não possui validação válida para sua conta. Gere um novo quiz; o resultado antigo não pode receber XP.",
            ) from None
    return correct


def conflict_insert(db, model):
    dialect = db.get_bind().dialect.name
    if dialect == "postgresql":
        return pg_insert(model)
    if dialect == "sqlite":
        return sqlite_insert(model)
    raise RuntimeError(f"Unsupported learning statistics database: {dialect}")


def claim_answer_receipts(db, user_id: int, event_id: str, answers: list):
    for answer in answers:
        statement = (
            conflict_insert(db, models.QuizAnswerCredit)
            .values(
                user_id=user_id,
                event_id=event_id,
                question_key=hashlib.sha256(answer.question_id.encode()).hexdigest(),
            )
            .on_conflict_do_nothing(index_elements=["user_id", "question_key"])
            .returning(models.QuizAnswerCredit.id)
        )
        # INSERT rowcount may be -1 even after a successful write. RETURNING
        # distinguishes an actual inserted receipt from ON CONFLICT DO NOTHING.
        if db.execute(statement).scalar_one_or_none() is None:
            raise HTTPException(
                422,
                "Esta questão já foi contabilizada. Gere um novo quiz para uma nova sessão.",
            )


def increment_daily(db, user_id: int, *, total: int, correct: int, xp: int):
    table = models.QuizStatsDaily
    statement = conflict_insert(db, table).values(
        user_id=user_id,
        day_key=datetime.now(timezone.utc).date(),
        questoes=total,
        acertos=correct,
        xp_ganho=xp,
        updated_at=datetime.now(timezone.utc),
    )
    db.execute(
        statement.on_conflict_do_update(
            index_elements=["user_id", "day_key"],
            set_={
                "questoes": func.coalesce(table.questoes, 0) + total,
                "acertos": func.coalesce(table.acertos, 0) + correct,
                "xp_ganho": func.coalesce(table.xp_ganho, 0) + xp,
                "updated_at": datetime.now(timezone.utc),
            },
        )
    )
