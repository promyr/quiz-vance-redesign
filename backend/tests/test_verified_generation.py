import json

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from app import models
from app.routers import quiz


@pytest.fixture
def generation(monkeypatch):
    engine = create_engine("sqlite+pysqlite:///:memory:")
    models.Base.metadata.create_all(engine)
    with Session(engine) as db:
        student = models.User(
            name="QA", login_id="qa", email_id="qa@test.invalid", password_hash="test"
        )
        db.add(student)
        db.commit()
        monkeypatch.setattr(
            quiz, "_require_user", lambda authorization, session: student
        )
        monkeypatch.setattr(quiz, "_is_premium", lambda *args: True)
        monkeypatch.setattr(quiz, "_check_simulado_limit", lambda *args: None)
        monkeypatch.setattr(
            quiz.SmartQuestionCache,
            "get_candidate_questions",
            lambda *args, **kwargs: [],
        )
        usage = []
        monkeypatch.setattr(
            quiz, "_increment_usage", lambda *args: usage.append(args[-1])
        )
        yield db, usage
    engine.dispose()


def question(n):
    return {
        "pergunta": f"Quanto é {n}+{n}?",
        "opcoes": [str(2 * n), str(2 * n + 1)],
        "correta_index": 0,
        "explicacao": "original",
    }


@pytest.mark.parametrize("feature,quantity", [("quiz", 3), ("simulado", 5)])
def test_partial_generation_refills_and_reviews_before_delivery(
    generation, monkeypatch, feature, quantity
):
    db, usage = generation
    calls = []
    batches = [list(range(1, quantity)), [quantity]]

    def provider(*args, **kwargs):
        calls.append(kwargs)
        if "revisor independente" in kwargs["system_prompt"].lower():
            payload = json.loads(kwargs["user_prompt"])
            assert all(
                "correctOptionId" not in q and "explanation" not in q for q in payload
            )
            return json.dumps(
                [
                    {
                        "id": q["id"],
                        "valid": True,
                        "correct_index": 0,
                        "solution": "Soma verificada de parcelas iguais.",
                    }
                    for q in payload
                ]
            ), "fake"
        return json.dumps([question(n) for n in batches.pop(0)]), "fake"

    monkeypatch.setattr(quiz, "_call_ai_for_user", provider)
    body = (
        quiz.QuizGenerateIn(topic="Matemática", quantity=quantity)
        if feature == "quiz"
        else quiz.SimuladoGenerateIn(topic="Matemática", quantity=quantity)
    )
    result = (quiz.generate_quiz if feature == "quiz" else quiz.generate_simulado)(
        body, "qa", db
    )
    assert len(result["questions"]) == quantity
    assert len(calls) == 4
    assert all(
        q["explanation"] == "Soma verificada de parcelas iguais."
        for q in result["questions"]
    )
    assert len(usage) == 1


def test_incomplete_verified_batch_is_not_delivered_or_charged(generation, monkeypatch):
    db, usage = generation

    def provider(*args, **kwargs):
        if "revisor independente" in kwargs["system_prompt"].lower():
            return "[]", "fake"
        return json.dumps([question(1)]), "fake"

    monkeypatch.setattr(quiz, "_call_ai_for_user", provider)
    with pytest.raises(HTTPException) as error:
        quiz.generate_quiz(
            quiz.QuizGenerateIn(topic="Matemática", quantity=3), "qa", db
        )
    assert error.value.status_code == 502
    assert usage == []


def test_old_cache_is_reviewed_and_disagreement_cannot_be_delivered(
    generation, monkeypatch
):
    db, usage = generation
    cached = quiz.ai.normalize_quiz_questions([question(1)])
    monkeypatch.setattr(
        quiz.SmartQuestionCache,
        "get_candidate_questions",
        lambda *args, **kwargs: cached,
    )

    def provider(*args, **kwargs):
        if "revisor independente" in kwargs["system_prompt"].lower():
            return json.dumps(
                [
                    {
                        "id": 0,
                        "valid": True,
                        "correct_index": 1,
                        "solution": "Outra alternativa.",
                    }
                ]
            ), "fake"
        return json.dumps([question(2)]), "fake"

    monkeypatch.setattr(quiz, "_call_ai_for_user", provider)
    with pytest.raises(HTTPException):
        quiz.generate_quiz(
            quiz.QuizGenerateIn(topic="Matemática", quantity=1), "qa", db
        )
    assert usage == []
