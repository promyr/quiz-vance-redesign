"""Teste do router real com resposta IA fictícia, sem requisições externas."""

import json
from types import SimpleNamespace

import pytest
from fastapi import HTTPException

from app.routers import quiz


@pytest.fixture
def generate(monkeypatch):
    usage = []
    monkeypatch.setattr(quiz, "_require_user", lambda *args: SimpleNamespace(id=999))
    monkeypatch.setattr(quiz, "_is_premium", lambda *args: True)
    monkeypatch.setattr(quiz, "_load_seen_questions", lambda *args: [])
    monkeypatch.setattr(quiz, "_store_seen_questions", lambda *args: None)
    monkeypatch.setattr(quiz, "_signed_questions", lambda questions, *args: questions)
    monkeypatch.setattr(quiz, "_increment_usage", lambda *args: usage.append("charged"))

    def call(questions):
        def provider(*args, **kwargs):
            if "revisor independente" in kwargs.get("system_prompt", "").lower():
                items = json.loads(kwargs["user_prompt"])
                return json.dumps(
                    [
                        {
                            "id": item["id"],
                            "valid": True,
                            "concept_duplicate": False,
                            "correct_index": 1,
                            "solution": "Dois mais dois são quatro.",
                        }
                        for item in items
                    ]
                ), "qa"
            return json.dumps(questions), "qa"

        monkeypatch.setattr(
            quiz,
            "_call_ai_for_user",
            provider,
        )
        return quiz.generate_quiz(
            quiz.QuizGenerateIn(
                topic="Matemática", quantity=1, context="Fixture de estudo isolada."
            ),
            "test",
            None,
        )

    return call, usage


VALID = {"pergunta": "Quanto é 2 + 2?", "opcoes": ["3", "4"], "correta_index": 1}


def test_valid_batch_returns_correct_key_and_reserves_once(generate):
    call, usage = generate
    result = call([VALID])
    assert result["questions"][0]["options"][1]["isCorrect"]
    assert usage == ["charged"]


def test_empty_batch_does_not_consume_quota(generate):
    call, usage = generate
    with pytest.raises(HTTPException) as error:
        call([])
    assert error.value.status_code == 502
    assert usage == []


def test_invalid_key_not_returned_or_charged(generate):
    call, usage = generate
    with pytest.raises(HTTPException) as error:
        call([{**VALID, "correta_index": "indefinido"}])
    assert error.value.status_code == 502
    assert usage == []


def test_one_malformed_association_does_not_destroy_other_valid_questions(generate):
    call, usage = generate
    bad = {
        "pergunta": "Associe.",
        "tipo": "associacao",
        "opcoes": 1,
        "coluna_esquerda": [{"id": "I", "texto": "A"}, {"id": "II", "texto": "B"}],
        "coluna_direita": [{"id": "1", "texto": "A"}, {"id": "2", "texto": "B"}],
    }
    result = call([VALID, bad])
    assert len(result["questions"]) == 1
    assert usage == ["charged"]
