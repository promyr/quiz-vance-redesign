from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app import ai_service as ai
from app import models
from app.routers import quiz
from app.smart_cache_service import SmartQuestionCache


def test_store_and_load_seen_questions():
    engine = create_engine(
        'sqlite+pysqlite:///:memory:',
        connect_args={'check_same_thread': False},
        poolclass=StaticPool,
    )
    models.Base.metadata.create_all(engine)
    with Session(engine) as db:
        user = models.User(
            name='tester',
            login_id='tester',
            email_id='tester@test.invalid',
            password_hash='test-only',
        )
        db.add(user)
        db.commit()

        # Testa gravação tanto com formato Flutter ("text") quanto legado ("pergunta")
        questions = [
            {'text': 'Qual o principio da legalidade?', 'id': '1'},
            {'pergunta': 'Qual o conceito de ato administrativo?', 'id': '2'},
        ]
        topic = 'Direito Administrativo'
        tk = quiz._topic_key(topic)

        quiz._store_seen_questions(db, user.id, tk, questions)

        seen = quiz._load_seen_questions(db, user.id, tk)
        assert len(seen) == 2
        assert 'Qual o principio da legalidade?' in seen
        assert 'Qual o conceito de ato administrativo?' in seen

        # Verifica persistência no banco QuizSeenQuestion
        records = db.query(models.QuizSeenQuestion).filter_by(user_id=user.id).all()
        assert len(records) == 2

    engine.dispose()


def test_smart_cache_methods_exist_and_execute():
    engine = create_engine(
        'sqlite+pysqlite:///:memory:',
        connect_args={'check_same_thread': False},
        poolclass=StaticPool,
    )
    models.Base.metadata.create_all(engine)
    with Session(engine) as db:
        user = models.User(
            name='tester2',
            login_id='tester2',
            email_id='tester2@test.invalid',
            password_hash='test-only',
        )
        db.add(user)
        db.commit()

        # Chama get_candidate_questions (método que antes dava AttributeError)
        candidates = SmartQuestionCache.get_candidate_questions(
            db, topic='Biologia Celular', difficulty='intermediario', limit=10
        )
        assert candidates == []

        # Chama store_questions (método que antes dava AttributeError)
        SmartQuestionCache.store_questions(
            db, topic='Biologia Celular', difficulty='intermediario', questions=[{'text': 'O que e mitocondria?'}]
        )

        # Insere uma questão vista
        tk = quiz._topic_key('Biologia Celular')
        quiz._store_seen_questions(db, user.id, tk, [{'text': 'O que e mitocondria?'}])

        # get_candidate_questions e get_cached_questions executam com segurança sem AttributeError
        candidates_after = SmartQuestionCache.get_candidate_questions(
            db, topic='Biologia Celular', difficulty='intermediario', limit=10
        )
        assert candidates_after == []

        cached = SmartQuestionCache.get_cached_questions(
            db, user_id=user.id, topic='Biologia Celular', quantity=5
        )
        assert cached == []

    engine.dispose()


def test_build_quiz_prompt_diversity_instructions():
    prompt = ai.build_quiz_prompt(
        topic='Historia do Brasil',
        difficulty='intermediario',
        quantity=5,
        avoid=['Quem proclamou a independencia?'],
    )
    assert 'Antes de escrever qualquer questao, enumere mentalmente' in prompt
    assert 'Varie o tipo cognitivo de cada questao' in prompt
    assert 'Quem proclamou a independencia?' in prompt
