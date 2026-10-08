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


@pytest.mark.parametrize('feature', ['quiz', 'simulado'])
def test_history_and_whitespace_duplicates_are_blocked_server_side(monkeypatch, feature):
    batches = [
        [question(1), question(2), dict(question(2), pergunta=' Quanto  é  2+2? ')],
        [question(3)],
    ]
    monkeypatch.setattr(quiz, '_call_ai_for_user',
        lambda *args, **kwargs: (json.dumps(batches.pop(0)), 'fake'))
    monkeypatch.setattr(quiz, '_review_question_batch',
        lambda user, db, provider, candidates, **kwargs: candidates)
    result = quiz._generate_verified_batch(None, None, feature=feature,
        topic='Matemática', difficulty='easy', quantity=2, context=None,
        provider=None, avoid=['Quanto é 1+1?'])
    assert [q['text'] for q in result] == ['Quanto é 2+2?', 'Quanto é 3+3?']


def test_cached_initial_batch_cannot_bypass_history_or_uniqueness(monkeypatch):
    initial = quiz.ai.normalize_quiz_questions([question(1), question(2), question(2)])
    monkeypatch.setattr(quiz, '_call_ai_for_user',
        lambda *args, **kwargs: (json.dumps([question(3)]), 'fake'))
    monkeypatch.setattr(quiz, '_review_question_batch',
        lambda user, db, provider, candidates, **kwargs: candidates)
    result = quiz._generate_verified_batch(None, None, feature='quiz',
        topic='Matemática', difficulty='easy', quantity=2, context=None,
        provider=None, avoid=['Quanto é 1+1?'], initial=initial)
    assert [q['text'] for q in result] == ['Quanto é 2+2?', 'Quanto é 3+3?']


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
                        "concept_duplicate": False,
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
                        "concept_duplicate": False,
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


@pytest.mark.parametrize("intervening,blocked", [(19, True), (20, False)])
def test_repeat_requires_twenty_other_questions(generation, intervening, blocked):
    db, _ = generation
    topic = quiz._topic_key("Matemática")
    original = {"text": "Pergunta original"}
    quiz._store_seen_questions(db, 1, topic, [original])
    quiz._store_seen_questions(db, 1, topic, [
        {"text": f"Outra pergunta {n}"} for n in range(intervening)
    ])
    assert (original["text"] in quiz._load_seen_questions(db, 1, topic)) is blocked
    if not blocked:
        quiz._store_seen_questions(db, 1, topic, [original])
        assert quiz._load_seen_questions(db, 1, topic)[0] == original["text"]


def test_other_subject_does_not_advance_repeat_interval(generation):
    db, _ = generation
    quiz._store_seen_questions(db, 1, "matemática", [{"text": "Original"}])
    quiz._store_seen_questions(db, 1, "biologia", [
        {"text": f"Biologia {n}"} for n in range(25)
    ])
    assert quiz._load_seen_questions(db, 1, "matemática") == ["Original"]
