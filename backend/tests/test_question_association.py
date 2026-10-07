from app import ai_service
from app.question_structure import complete_cached_questions


def test_association_preserves_both_columns_and_propositions():
    question = {'pergunta': 'Associe as colunas.', 'tipo': 'associacao',
                'coluna_esquerda': [{'id': 'I', 'texto': 'Evaporação'}, {'id': 'II', 'texto': 'Condensação'}],
                'coluna_direita': [{'id': '1', 'texto': 'Líquido para gás'}, {'id': '2', 'texto': 'Gás para líquido'}],
                'opcoes': ['I-1; II-2', 'I-2; II-1'], 'correta_index': 0}
    normalized = ai_service.normalize_quiz_questions([question])
    assert len(normalized) == 1
    assert 'I — Evaporação' in normalized[0]['text']
    assert '2 — Gás para líquido' in normalized[0]['text']
    assert normalized[0]['association']['left'][0]['text'] == 'Evaporação'


def test_incomplete_association_is_not_presented_to_student():
    question = {'pergunta': 'Associe as colunas.', 'tipo': 'associacao',
                'opcoes': ['I-1; II-2', 'I-2; II-1'], 'correta_index': 0}
    assert ai_service.normalize_quiz_questions([question]) == []


def test_assertion_question_preserves_propositions():
    question = {'pergunta': 'Avalie as proposições.', 'proposicoes': ['O calor é energia.', 'O gelo é um gás.'],
                'opcoes': ['Apenas I', 'Apenas II'], 'correta_index': 0}
    normalized = ai_service.normalize_quiz_questions([question])
    assert '1 — O calor é energia.' in normalized[0]['text']
    assert '2 — O gelo é um gás.' in normalized[0]['text']


def test_inline_association_remains_compatible():
    question = {'pergunta': 'Associe: I) Evaporação II) Condensação\n1) Líquido para gás 2) Gás para líquido',
                'opcoes': ['I-1; II-2', 'I-2; II-1'], 'correta_index': 0}
    assert len(ai_service.normalize_quiz_questions([question])) == 1


def test_generation_prompts_require_complete_association_structure():
    for prompt in [ai_service.build_quiz_prompt('Ciências', 'facil', 2),
                   ai_service.build_simulado_prompt('Ciências', 'facil', 2)]:
        assert 'coluna_esquerda' in prompt
        assert 'coluna_direita' in prompt
        assert 'proposicoes' in prompt


def test_cached_incomplete_association_is_discarded():
    cached = [{'id': 'old', 'text': 'Associe as colunas.', 'options': []},
              {'id': 'valid', 'text': 'O que é calor?', 'options': []}]
    assert [q['id'] for q in complete_cached_questions(cached)] == ['valid']


def test_typed_inline_association_accepts_letter_and_numeric_columns():
    question = {'pergunta': 'Associe: A) Evaporação B) Condensação\n1) Líquido para gás 2) Gás para líquido',
                'tipo': 'associacao', 'opcoes': ['A-1; B-2', 'A-2; B-1'], 'correta_index': 0}
    assert len(ai_service.normalize_quiz_questions([question])) == 1


def test_numbers_alone_do_not_prove_both_columns_exist():
    question = {'pergunta': 'Associe as colunas. Dados: 1) 2001 2) 2002 3) 2003 4) 2004',
                'opcoes': ['I-1; II-2', 'I-2; II-1'], 'correta_index': 0}
    assert ai_service.normalize_quiz_questions([question]) == []


def test_mentions_of_premises_do_not_replace_labeled_columns():
    question = {'pergunta': 'Associe água e gelo.', 'tipo': 'associacao',
                'coluna_esquerda': [{'id': 'I', 'texto': 'água'}, {'id': 'II', 'texto': 'gelo'}],
                'coluna_direita': [{'id': '1', 'texto': 'água'}, {'id': '2', 'texto': 'gelo'}],
                'opcoes': ['I-1; II-2', 'I-2; II-1'], 'correta_index': 0}
    text = ai_service.normalize_quiz_questions([question])[0]['text']
    assert 'Coluna I\nI — água\nII — gelo' in text
    assert 'Coluna II\n1 — água\n2 — gelo' in text


def test_recorded_association_edge_cases_keep_valid_questions_and_reject_incomplete_ones():
    import json
    from pathlib import Path

    cases = json.loads((Path(__file__).parent / "fixtures/association_edge_cases.json").read_text(encoding="utf-8"))
    for case in cases:
        result = ai_service.normalize_quiz_questions([case["input"]])
        assert bool(result) == case["expected"], case["name"]
        assert complete_cached_questions(complete_cached_questions(result)) == complete_cached_questions(result), case["name"]


def test_numeric_association_sequences_validate_right_column_references():
    question = {"pergunta": "Associe as colunas.", "tipo": "associação", "coluna_esquerda": [{"id": "I", "texto": "Um"}, {"id": "II", "texto": "Dois"}], "coluna_direita": [{"id": "1", "texto": "One"}, {"id": "2", "texto": "Two"}], "opcoes": ["1 - 2", "2 - 1"], "correta_index": 0}
    assert len(ai_service.normalize_quiz_questions([question])) == 1
    question["opcoes"][0] = "3, 2"
    assert ai_service.normalize_quiz_questions([question]) == []
    question["opcoes"][0] = "1, 2"
    question["coluna_esquerda"][0]["id"] = None
    assert ai_service.normalize_quiz_questions([question]) == []
