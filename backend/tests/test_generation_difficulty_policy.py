import pytest

from app import ai_service as ai
from app.routers.quiz import OpenGenerateIn, QuizGenerateIn, SimuladoGenerateIn


@pytest.mark.parametrize('legacy', ['easy', 'medium', 'facil', 'intermediario', 'mixed'])
def test_legacy_requests_cannot_select_easy_generation(legacy):
    assert QuizGenerateIn(topic='Valvulas', difficulty=legacy).difficulty == 'mixed'
    assert SimuladoGenerateIn(topic='Valvulas', difficulty=legacy).difficulty == 'mixed'
    assert OpenGenerateIn(tema='Valvulas', dificuldade=legacy).dificuldade == 'mixed'


def test_generation_defaults_are_mixed_and_hard_remains_supported():
    assert QuizGenerateIn(topic='Valvulas').difficulty == 'mixed'
    assert SimuladoGenerateIn().difficulty == 'mixed'
    assert OpenGenerateIn(tema='Valvulas').dificuldade == 'mixed'
    assert QuizGenerateIn(topic='Valvulas', difficulty='hard').difficulty == 'hard'
    assert SimuladoGenerateIn(difficulty='dificil').difficulty == 'hard'
    assert OpenGenerateIn(tema='Valvulas', dificuldade='hard').dificuldade == 'hard'


@pytest.mark.parametrize('builder', [ai.build_quiz_prompt, ai.build_simulado_prompt])
def test_objective_prompts_explicitly_exclude_easy_questions(builder):
    prompt = builder('Valvulas', 'mixed', 10)
    assert 'MISTO (MEDIO E DIFICIL)' in prompt
    assert 'Nao gere questoes faceis' in prompt
    assert 'Dificuldade alvo: DIFICIL' in builder('Valvulas', 'hard', 10)


def test_open_question_uses_same_mixed_policy():
    prompt = ai.build_open_question_prompt('Valvulas', 'easy')
    assert 'MISTO (MEDIO E DIFICIL)' in prompt
    assert 'Nao gere questoes faceis' in prompt
