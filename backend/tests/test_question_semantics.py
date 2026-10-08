import json

import pytest

from app.ai_service import normalize_quiz_questions


def test_triangle_345_without_axis_has_two_true_options_and_is_rejected():
    from app.question_validation import semantic_question_is_valid

    question = {
        "pergunta": "Um triângulo tem lados de 3 cm, 4 cm e 5 cm. Qual é o tipo de triângulo?",
        "opcoes": ["Escaleno", "Isósceles", "Retângulo", "Obtuso"],
        "correta_index": 2,
    }
    assert not semantic_question_is_valid(question)


@pytest.mark.parametrize("axis,index", [("lados", 0), ("ângulos", 2)])
def test_triangle_explicit_classification_axis_is_preserved(axis, index):
    from app.question_validation import semantic_question_is_valid

    question = {
        "pergunta": f"Um triângulo tem lados de 3 cm, 4 cm e 5 cm. Qual é o tipo de triângulo quanto aos {axis}?",
        "opcoes": ["Escaleno", "Isósceles", "Retângulo", "Obtuso"],
        "correta_index": index,
    }
    assert semantic_question_is_valid(question)


@pytest.mark.parametrize(
    "lengths", ["3/2 cm, 4 cm e 5 cm", "3 cm, 4 m e 5 cm", "3,5 cm, 4 cm e 5 cm"]
)
def test_triangle_unsupported_units_or_fractional_sides_left_to_review(lengths):
    from app.question_validation import _triangle_answer

    assert (
        _triangle_answer(
            f"Um triângulo tem lados de {lengths}. Qual é o tipo de triângulo?",
            ["Escaleno", "Isósceles", "Retângulo", "Obtuso"],
            2,
        )
        is None
    )


def test_single_fair_die_thrown_twice_wrong_key_is_rejected():
    from app.question_validation import semantic_question_is_valid

    question = {
        "pergunta": "Um dado justo é lançado duas vezes. Qual a probabilidade de a soma dos resultados ser 7?",
        "opcoes": ["1/6", "1/12", "5/36", "1/3"],
        "correta_index": 2,
    }
    assert not semantic_question_is_valid(question)
    assert semantic_question_is_valid({**question, "correta_index": 0})
    assert semantic_question_is_valid(
        {
            **question,
            "pergunta": "Um dado justo de seis faces é lançado duas vezes. Qual a probabilidade de a soma ser 7?",
            "correta_index": 0,
        }
    )


def test_polynomial_options_with_function_prefix_are_compared_numerically():
    from app.question_validation import semantic_question_is_valid

    question = {
        "pergunta": "Se f(x)=3x²+2x-5, qual é f(2)?",
        "opcoes": ["f(2)=11", "f(2)=17", "f(2)=19", "f(2)=13"],
        "correta_index": 0,
    }
    assert semantic_question_is_valid(question)
    assert not semantic_question_is_valid({**question, "correta_index": 1})
    assert not semantic_question_is_valid(
        {**question, "opcoes": ["f(3)=11", "f(2)=17", "f(2)=19", "f(2)=13"]}
    )


@pytest.mark.parametrize(
    "text",
    [
        "Dois dados de oito faces são lançados. Qual a probabilidade de a soma ser 7?",
        "Um dado justo é lançado duas vezes. Dado que o primeiro resultado é 1, qual a probabilidade de a soma ser 7?",
        "Dois dados são lançados. Qual a probabilidade de a soma ser 7 ou 8?",
        "Um dado justo é lançado duas vezes. Qual a probabilidade de a soma ser 7 e os números serem diferentes?",
        "Um dado viciado é lançado duas vezes. Qual a probabilidade da soma ser 7?",
    ],
)
def test_different_sample_spaces_are_left_to_independent_review(text):
    from app.question_validation import _expected_answer

    assert _expected_answer(text) is None


def test_real_polynomial_without_correct_alternative_is_rejected():
    question = {
        "pergunta": "Se f(x)=3x²+2x-5, qual é f(2)?",
        "opcoes": ["17", "15", "19", "13"],
        "correta_index": 0,
        "explicacao": "O resultado é 11; deve-se corrigir o enunciado para obter 13.",
    }
    assert normalize_quiz_questions([question]) == []


def test_real_dice_wrong_key_is_rejected():
    question = {
        "pergunta": "Qual a probabilidade da soma de dois dados ser 7?",
        "opcoes": ["1/6", "1/12", "5/36", "1/3"],
        "correta_index": 2,
        "explicacao": "São seis resultados em 36, portanto 6/36 = 1/6. (Revisar)",
    }
    assert normalize_quiz_questions([question]) == []


def test_blind_review_rejects_disagreement_and_missing_verdict():
    from app.question_validation import verify_questions_with_ai

    raw = [{"pergunta": "Quanto é 2+2?", "opcoes": ["4", "5"], "correta_index": 0}]
    assert (
        verify_questions_with_ai(
            raw,
            lambda **kwargs: json.dumps([{"id": 0, "valid": True, "correct_index": 1}]),
        )
        == []
    )
    assert verify_questions_with_ai(raw, lambda **kwargs: "[]") == []


def test_blind_review_does_not_receive_key_or_explanation():
    from app.question_validation import verify_questions_with_ai

    raw = [
        {
            "pergunta": "Quanto é 2+2?",
            "opcoes": ["4", "5"],
            "correta_index": 0,
            "explicacao": "SEGREDO_GABARITO",
        }
    ]

    def review(**kwargs):
        assert "SEGREDO_GABARITO" not in kwargs["user_prompt"]
        assert "correta_index" not in kwargs["user_prompt"]
        return json.dumps(
            [
                {
                    "id": 0,
                    "valid": True,
                    "correct_index": 0,
                    "solution": "Dois mais dois são quatro.",
                }
            ]
        )

    verified = verify_questions_with_ai(raw, review)
    assert verified[0]["explicacao"] == "Dois mais dois são quatro."
    assert raw[0]["explicacao"] == "SEGREDO_GABARITO"


def test_review_rejects_missing_solution():
    from app.question_validation import verify_questions_with_ai

    raw = [
        {
            "pergunta": "Quanto é 2+2?",
            "opcoes": ["4", "5"],
            "correta_index": 0,
            "explicacao": "São cinco.",
        }
    ]
    assert (
        verify_questions_with_ai(
            raw,
            lambda **kwargs: json.dumps([{"id": 0, "valid": True, "correct_index": 0}]),
        )
        == []
    )


def test_valid_polynomial_and_equivalent_fraction_are_preserved():
    from app.question_validation import semantic_question_is_valid

    assert semantic_question_is_valid(
        {
            "pergunta": "Se f(x)=3x²+2x-5, qual é f(2)?",
            "opcoes": ["11", "15", "19", "13"],
            "correta_index": 0,
        }
    )
    assert semantic_question_is_valid(
        {
            "pergunta": "Qual a probabilidade da soma de dois dados ser 7?",
            "opcoes": ["6/36", "1/12", "5/36", "1/3"],
            "correta_index": 0,
        }
    )


def test_duplicate_reviewer_verdict_and_malformed_json_are_rejected():
    from app.question_validation import verify_questions_with_ai

    raw = [{"pergunta": "Quanto é 2+2?", "opcoes": ["4", "5"], "correta_index": 0}]
    verdict = {"id": 0, "valid": True, "correct_index": 0, "solution": "Quatro."}
    assert (
        verify_questions_with_ai(raw, lambda **kwargs: json.dumps([verdict, verdict]))
        == []
    )
    assert verify_questions_with_ai(raw, lambda **kwargs: "not json") == []
