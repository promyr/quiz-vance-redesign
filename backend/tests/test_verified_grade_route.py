import json
from types import SimpleNamespace

import pytest
from fastapi import HTTPException

from app.routers import quiz


@pytest.mark.parametrize("valid", [True, False])
def test_grade_route_preserves_zero_and_blocks_factual_disagreement(monkeypatch, valid):
    monkeypatch.setattr(quiz, "_require_user", lambda *args: SimpleNamespace(id=1))
    grade = {
        "nota": 0,
        "correto": False,
        "feedback": "A resposta usa MDC no lugar de MMC.",
        "pontos_fortes": [],
        "pontos_melhorar": ["Diferencie divisor de múltiplo."],
        "criterios": {"aderencia": 0},
    }
    calls = []

    def provider(*args, **kwargs):
        calls.append(kwargs)
        return json.dumps(grade if len(calls) == 1 else {"valid": valid}), "qa"

    monkeypatch.setattr(quiz, "_call_ai_for_user", provider)
    body = quiz.OpenGradeIn(
        pergunta="Explique o MMC.",
        resposta_esperada="Mínimo múltiplo comum.",
        resposta_aluno="É o máximo divisor comum.",
    )
    if valid:
        assert quiz.grade_open_answer(body, "qa", None)["nota"] == 0
    else:
        with pytest.raises(HTTPException) as error:
            quiz.grade_open_answer(body, "qa", None)
        assert error.value.status_code == 502
    assert len(calls) == 2
