from app.ai_service import build_quiz_prompt


def test_explicit_session_topics_receive_balanced_question_counts():
    prompt = build_quiz_prompt('Portugues: Sintaxe; Morfologia; Semantica', 'medium', 8)
    assert 'Sintaxe: 3 questoes' in prompt
    assert 'Morfologia: 3 questoes' in prompt
    assert 'Semantica: 2 questoes' in prompt


def test_fewer_questions_than_topics_rotates_coverage_using_previous_questions():
    prompt = build_quiz_prompt('Direito: Constitucional; Administrativo; Penal', 'medium', 2, avoid=['seen'])
    assert 'Administrativo: 1 questoes' in prompt
    assert 'Penal: 1 questoes' in prompt
