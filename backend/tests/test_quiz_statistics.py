from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app import models
from app.database import get_db
from app.routers import quiz, user


def test_quiz_results_update_account_statistics_without_duplicate_counting(monkeypatch):
    engine = create_engine('sqlite+pysqlite:///:memory:', connect_args={'check_same_thread': False}, poolclass=StaticPool)
    models.Base.metadata.create_all(engine)
    with Session(engine) as db:
        accounts = [models.User(name=name, login_id=name, email_id=f'{name}@test.invalid', password_hash='test-only') for name in ['student', 'other']]
        db.add_all(accounts)
        db.commit()
        ids = {account.login_id: account.id for account in accounts}
        monkeypatch.setattr(quiz, '_require_user', lambda authorization, session: session.get(models.User, ids[authorization]))
        monkeypatch.setattr(user, '_require_user', lambda authorization, session: session.get(models.User, ids[authorization]))
        app = FastAPI()
        app.include_router(quiz.router)
        app.include_router(user.router)
        app.dependency_overrides[get_db] = lambda: db
        client = TestClient(app)
        headers = {'Authorization': 'student'}
        signed = quiz._signed_questions([
            {'id': str(i), 'correct_option_id': 'A', 'options': [{'id':'A'}, {'id':'B'}]} for i in range(3)
        ], ids['student'], 'quiz')
        def answer(i, selected):
            return {'question_id':signed[i]['id'], 'selected_option_id':selected, 'is_correct':selected=='A'}
        body = {'session_id': 'completed', 'total': 2, 'correct': 1, 'xp_earned': 10, 'answers':[answer(0,'A'),answer(1,'B')]}
        assert client.post('/quiz/submit', headers=headers, json=body).status_code == 200
        assert client.post('/quiz/submit', headers=headers, json=body).status_code == 200
        assert client.post('/quiz/submit', headers=headers, json={'session_id': 'partial', 'total': 1, 'correct': 0, 'answers':[answer(2,'B')]}).status_code == 200
        stats = client.get('/user/stats', headers=headers).json()
        assert stats['total_questoes'] == stats['today_questoes'] == 3
        assert stats['total_acertos'] == stats['today_acertos'] == 1
        assert stats['total_xp'] == stats['today_xp'] == 10
        other = client.get('/user/stats', headers={'Authorization': 'other'}).json()
        assert other['total_questoes'] == other['total_xp'] == 0
        for period in ('weekly', 'monthly', 'alltime', 'global'):
            ranking_resp = client.get(f'/ranking/{period}', headers=headers)
            assert ranking_resp.status_code == 200
            ranking_payload = ranking_resp.json()
            assert ranking_payload['current_user_position'] == 1
            assert len(ranking_payload['ranking']) == 1
            top = ranking_payload['ranking'][0]
            assert top['name'] == 'student'
            assert top['xp'] == 10
            assert top['is_current_user'] is True
            assert round(top['accuracy'], 1) == 33.3
    engine.dispose()
