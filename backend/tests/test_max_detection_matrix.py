"""Adversarial JSON and damaged cache probes; no production data or providers."""

from itertools import product

import pytest

from app.ai_service import normalize_quiz_questions
from app.question_structure import complete_cached_questions

BASE = {
    "pergunta": "Quanto resulta dois mais dois?",
    "opcoes": ["Quatro", "Tres"],
    "correta_index": 0,
}


@pytest.mark.parametrize("value", [42, True, ["texto"], {"texto": "questao"}])
def test_non_text_statement_is_rejected_instead_of_displaying_json(value):
    assert normalize_quiz_questions([{**BASE, "pergunta": value}]) == []


@pytest.mark.parametrize("value", [None, 42, True, "string", [], ["nested"]])
def test_malformed_cached_item_does_not_prevent_valid_cached_question(value):
    valid = {"id": "valid", "text": BASE["pergunta"], "options": ["Quatro", "Tres"]}
    result = complete_cached_questions([value, valid])
    assert len(result) == 1
    assert result[0]["id"] == "valid"


def test_json_matrix_does_not_crash_or_invent_correct_answer():
    options = [
        None,
        False,
        5,
        "A,B",
        {},
        [],
        [""],
        ["A"],
        ["A", None],
        ["A", "A"],
        [" A ", "A"],
        ["A", "B"],
        ["A", "B", "C", "D", "E"],
    ]
    indices = [None, False, True, -1, 0, 1, 4, 5, 100, "0", "4", "invalid", 1.5, {}, []]
    structures = [
        {},
        {"association": None},
        {"association": []},
        {"tipo": "associacao"},
        {"proposicoes": []},
        {"coluna_esquerda": 5, "coluna_direita": True},
    ]
    count = 0
    for choices, index, metadata in product(options, indices, structures):
        result = normalize_quiz_questions(
            [{**BASE, "opcoes": choices, "correta_index": index, **metadata}]
        )
        for question in result:
            correct = [option for option in question["options"] if option["isCorrect"]]
            assert len(correct) == 1
            assert question["correctOptionId"] == correct[0]["id"]
            assert len(question["options"]) == len(choices)
        count += 1
    assert count == 1170
