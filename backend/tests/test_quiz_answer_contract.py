"""Probes isolados: não modificam dados ou código do produto."""

import copy

import pytest

from app.ai_service import normalize_quiz_questions
from app.question_structure import complete_cached_questions

BASE = {
    "pergunta": "Qual o resultado de 2 + 2?",
    "opcoes": ["3", "4", "5", "6"],
    "correta_index": 1,
}


@pytest.mark.parametrize("value", [-1, 99, "invalido", None])
def test_invalid_answer_index_is_rejected_instead_of_inventing_answer(value):
    q = {**BASE, "correta_index": value}
    assert normalize_quiz_questions([q]) == []


def test_missing_answer_key_is_rejected():
    q = copy.deepcopy(BASE)
    del q["correta_index"]
    assert normalize_quiz_questions([q]) == []


def test_correct_fifth_option_not_silently_replaced_by_first():
    q = {**BASE, "opcoes": ["1", "2", "3", "4", "5"], "correta_index": 4}
    result = normalize_quiz_questions([q])
    assert not result or any(
        o["text"] == "5" and o["isCorrect"] for o in result[0]["options"]
    )


@pytest.mark.parametrize("options", [[None, "4"], ["", "4"], ["4", "4"]])
def test_blank_or_duplicate_alternatives_rejected(options):
    assert normalize_quiz_questions([{**BASE, "opcoes": options}]) == []


@pytest.mark.parametrize("value", [0, 1, True, {}, "invalid", None])
def test_malformed_association_options_do_not_crash_whole_generation(value):
    q = {
        **BASE,
        "pergunta": "Associe as colunas.",
        "tipo": "associacao",
        "coluna_esquerda": [{"id": "I", "texto": "Um"}, {"id": "II", "texto": "Dois"}],
        "coluna_direita": [{"id": "1", "texto": "One"}, {"id": "2", "texto": "Two"}],
        "opcoes": value,
    }
    assert normalize_quiz_questions([q]) == []


@pytest.mark.parametrize("size", range(2, 13))
def test_valid_associations_multiple_sizes_preserve_labels_cache_and_key(size):
    labels = [chr(65 + i) for i in range(size)]
    left = [{"id": x, "texto": "Left " + x} for x in labels]
    right = [{"id": str(i + 1), "texto": "Right " + str(i + 1)} for i in range(size)]
    first = "; ".join(f"{x}-{i + 1}" for i, x in enumerate(labels))
    second = "; ".join(f"{x}-{(i + 1) % size + 1}" for i, x in enumerate(labels))
    q = {
        **BASE,
        "pergunta": "Associe as colunas.",
        "tipo": "associação",
        "coluna_esquerda": left,
        "coluna_direita": right,
        "opcoes": [first, second],
        "correta_index": 0,
    }
    result = normalize_quiz_questions([q])
    assert len(result) == 1
    assert len(result[0]["association"]["left"]) == size
    cached = complete_cached_questions(result)
    assert cached == complete_cached_questions(cached)
    assert result[0]["options"][0]["isCorrect"]
