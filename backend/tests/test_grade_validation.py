import json

import pytest

from app.grade_validation import review_grade, validate_grade

BASE = {
    "nota": 0,
    "correto": False,
    "feedback": "MDC é o maior divisor comum; MMC é o menor múltiplo comum.",
    "pontos_fortes": [],
    "pontos_melhorar": ["Distinguir divisores de múltiplos."],
    "criterios": {"aderencia": 0, "estrutura": 20, "clareza": 20, "fundamentacao": 0},
}


def test_zero_is_preserved():
    assert validate_grade(BASE)["nota"] == 0


@pytest.mark.parametrize(
    "patch",
    [
        {"nota": True},
        {"nota": -1},
        {"nota": 101},
        {"nota": "0"},
        {"nota": float("nan")},
        {"correto": "false"},
        {"correto": True},
        {"feedback": {}},
        {"feedback": " "},
        {"pontos_fortes": [42]},
        {"pontos_melhorar": "texto"},
        {"criterios": {"aderencia": True}},
        {"criterios": {"aderencia": 101}},
    ],
)
def test_invalid_contract_rejected(patch):
    with pytest.raises(ValueError):
        validate_grade({**BASE, **patch})


@pytest.mark.parametrize(
    "response", ["invalid", "{}", '{"valid": "true"}', '{"valid": false}']
)
def test_uncertain_or_disagreeing_reviewer_rejected(response):
    with pytest.raises(ValueError):
        review_grade(
            pergunta="Explique MDC e MMC",
            resposta_esperada="MDC é múltiplo",
            resposta_aluno="MDC é divisor",
            proposed_grade=BASE,
            review_call=lambda **kwargs: response,
        )


def test_review_requires_factual_judgment_not_expected_answer_obedience():
    def reviewer(**kwargs):
        payload = json.loads(kwargs["user_prompt"])
        assert payload["resposta_esperada"] == "MDC é múltiplo"
        assert payload["resposta_aluno"] == "MDC é divisor"
        assert payload["avaliacao_proposta"]["nota"] == 0
        assert "MDC" in kwargs["system_prompt"] and "MMC" in kwargs["system_prompt"]
        return '{"valid": true}'

    assert (
        review_grade(
            pergunta="Explique MDC e MMC",
            resposta_esperada="MDC é múltiplo",
            resposta_aluno="MDC é divisor",
            proposed_grade=BASE,
            review_call=reviewer,
        )
        == BASE
    )
