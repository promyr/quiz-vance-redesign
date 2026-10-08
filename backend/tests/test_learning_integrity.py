from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine, func, select
from sqlalchemy.orm import Session

from app import models
from app.routers import flashcard, quiz


@pytest.fixture
def store(tmp_path, monkeypatch):
    engine = create_engine(
        f"sqlite+pysqlite:///{tmp_path / 'learning.sqlite'}",
        connect_args={"timeout": 30},
    )
    models.Base.metadata.create_all(engine)
    with Session(engine) as db:
        account = models.User(
            name="Student",
            login_id="student",
            email_id="student@test.invalid",
            password_hash="test-only",
        )
        db.add(account)
        db.commit()
        uid = account.id
    monkeypatch.setattr(
        quiz, "_require_user", lambda authorization, db: db.get(models.User, uid)
    )
    monkeypatch.setattr(
        flashcard, "_require_user", lambda authorization, db: db.get(models.User, uid)
    )
    yield engine, uid
    engine.dispose()


def trusted_answer(uid, *, selected="A", feature="quiz"):
    question = {
        "id": "question",
        "correct_option_id": "A",
        "options": [{"id": "A"}, {"id": "B"}],
    }
    signed = quiz._signed_questions([question], uid, feature)[0]
    return {
        "question_id": signed["id"],
        "selected_option_id": selected,
        "is_correct": selected == "A",
    }


def test_fresh_receipt_accepts_insert_when_driver_rowcount_is_unknown(store):
    """Some INSERT drivers return -1; a returned inserted row is authoritative."""
    engine, uid = store
    with Session(engine) as db:
        original_execute = db.execute

        class UnknownCount:
            rowcount = -1

            def __init__(self, result):
                self.result = result

            def __getattr__(self, name):
                return getattr(self.result, name)

        def execute(statement, *args, **kwargs):
            result = original_execute(statement, *args, **kwargs)
            if (
                getattr(getattr(statement, "table", None), "name", None)
                == "quiz_answer_credits"
            ):
                return UnknownCount(result)
            return result

        db.execute = execute
        body = quiz.QuizSubmitIn(
            session_id="unknown-count",
            total=1,
            correct=1,
            answers=[trusted_answer(uid)],
        )
        assert quiz.submit_quiz(body, "student", db)["xp_earned"] == 10
        assert quiz.submit_quiz(body, "student", db)["xp_earned"] == 10
        with pytest.raises(HTTPException) as error:
            quiz.submit_quiz(
                body.model_copy(update={"session_id": "duplicate"}), "student", db
            )
        assert error.value.status_code == 422
        daily = db.scalars(select(models.QuizStatsDaily)).one()
        assert (daily.questoes, daily.acertos, daily.xp_ganho) == (1, 1, 10)


def test_unanswered_claim_and_arbitrary_simulado_xp_are_rejected(store):
    engine, uid = store
    with Session(engine) as db:
        with pytest.raises(HTTPException) as error:
            quiz.submit_quiz(
                quiz.QuizSubmitIn(
                    total=1,
                    correct=1,
                    answers=[{"question_id": "unknown", "is_correct": False}],
                ),
                "student",
                db,
            )
        assert error.value.status_code == 422
        result = quiz.submit_simulado(
            quiz.SimuladoSubmitIn(
                total=1,
                correct=0,
                xp_earned=999,
                answers=[trusted_answer(uid, selected="B", feature="simulado")],
            ),
            "student",
            db,
        )
        assert result["xp_earned"] == 0
        assert db.get(models.User, uid).xp == 0


def test_signed_answer_reconciles_claim_and_user_and_replay(store):
    engine, uid = store
    with Session(engine) as db:
        body = quiz.QuizSubmitIn(
            session_id="one",
            total=1,
            correct=0,
            xp_earned=999,
            answers=[trusted_answer(uid)],
        )
        result = quiz.submit_quiz(body, "student", db)
        assert result["xp_earned"] == 10
        assert (
            quiz.submit_quiz(
                body.model_copy(update={"xp_earned": 99999}), "student", db
            )["xp_earned"]
            == 10
        )
        assert db.get(models.User, uid).xp == 10
        with pytest.raises(HTTPException):
            quiz.submit_quiz(
                body.model_copy(update={"session_id": "another-session"}), "student", db
            )
        assert db.get(models.User, uid).xp == 10
        bad = trusted_answer(uid + 1)
        with pytest.raises(HTTPException):
            quiz.submit_quiz(
                quiz.QuizSubmitIn(total=1, correct=1, answers=[bad]), "student", db
            )


def test_distinct_concurrent_sessions_preserve_daily_totals(store):
    engine, uid = store

    def submit(index):
        with Session(engine) as db:
            body = quiz.QuizSubmitIn(
                session_id=f"session-{index}",
                total=1,
                correct=1,
                answers=[trusted_answer(uid)],
            )
            return quiz.submit_quiz(body, "student", db)

    with ThreadPoolExecutor(max_workers=10) as pool:
        assert all(item["ok"] for item in pool.map(submit, range(20)))
    with Session(engine) as db:
        daily = db.scalars(select(models.QuizStatsDaily)).one()
        assert (daily.questoes, daily.acertos, daily.xp_ganho) == (20, 20, 200)
        assert db.scalar(select(func.count(models.QuizStatsEvent.id))) == 20
        assert db.get(models.User, uid).xp == 200


def test_remote_and_local_flashcards_credit_once_without_quiz_count(store):
    engine, uid = store
    with Session(engine) as db:
        body = flashcard.FlashcardReviewIn(
            flashcard_id="local-generated",
            front="Question",
            back="Answer",
            grade="good",
            reviewed_at=datetime.now(timezone.utc).isoformat(),
        )
        first = flashcard.review_flashcard(body, "student", db)
        replay = flashcard.review_flashcard(body, "student", db)
        assert first["xp_earned"] == 5
        assert replay["xp_earned"] == 0
        assert db.get(models.User, uid).xp == 5
        assert db.scalar(select(func.count(models.QuizStatsEvent.id))) == 0
        assert db.scalars(select(models.Flashcard)).one().repetitions == 1


def test_normalized_generation_can_be_signed_and_scored():
    from app import ai_service

    raw = [
        {
            "pergunta": "Qual alternativa está correta?",
            "opcoes": ["Resposta", "Errada", "Outra", "Nenhuma"],
            "correta_index": 0,
        }
    ]
    normalized = ai_service.normalize_quiz_questions(raw)
    assert normalized
    signed = quiz._signed_questions(normalized, 12, "quiz")
    answer = quiz.QuizAnswerIn(
        question_id=signed[0]["id"], selected_option_id=normalized[0]["correctOptionId"]
    )
    assert quiz.score_answers([answer], 1, 12, "quiz") == 1


def test_parallel_duplicate_session_is_credited_once(store):
    engine, uid = store
    answer = trusted_answer(uid)

    def submit(_):
        with Session(engine) as db:
            return quiz.submit_quiz(
                quiz.QuizSubmitIn(
                    session_id="same", total=1, correct=1, answers=[answer]
                ),
                "student",
                db,
            )

    with ThreadPoolExecutor(max_workers=10) as pool:
        assert all(result["xp_earned"] == 10 for result in pool.map(submit, range(10)))
    with Session(engine) as db:
        assert db.get(models.User, uid).xp == 10
        assert db.scalars(select(models.QuizStatsDaily)).one().questoes == 1


@pytest.mark.parametrize("feature", ["quiz", "simulado"])
def test_real_generation_route_to_submission_receipt_contract(
    store, monkeypatch, feature
):
    import json

    engine, _uid = store
    raw = [
        {
            "pergunta": f"Qual é o resultado de 2 mais {i}?",
            "opcoes": [str(2 + i), str(3 + i), str(4 + i), str(5 + i)],
            "correta_index": 0,
        }
        for i in range(5)
    ]

    def provider(*args, **kwargs):
        if "revisor independente" in kwargs.get("system_prompt", "").lower():
            items = json.loads(kwargs["user_prompt"])
            return json.dumps(
                [
                    {
                        "id": item["id"],
                        "valid": True,
                        "correct_index": 0,
                        "solution": "A soma é " + item["options"][0] + ".",
                    }
                    for item in items
                ]
            ), "qa"
        return json.dumps(raw), "qa"

    monkeypatch.setattr(quiz, "_call_ai_for_user", provider)
    with Session(engine) as db:
        if feature == "quiz":
            response = quiz.generate_quiz(
                quiz.QuizGenerateIn(
                    topic="Matemática", context="Material fonte", quantity=5
                ),
                "student",
                db,
            )
        else:
            response = quiz.generate_simulado(
                quiz.SimuladoGenerateIn(
                    topic="Matemática", context="Material fonte", quantity=5
                ),
                "student",
                db,
            )
        assert len(response["questions"]) == 5
        answers = [
            {"question_id": q["id"], "selected_option_id": q["correctOptionId"]}
            for q in response["questions"]
        ]
        assert all(answer["question_id"].startswith("qv1.") for answer in answers)
        if feature == "quiz":
            result = quiz.submit_quiz(
                quiz.QuizSubmitIn(
                    session_id="generated", total=5, correct=0, answers=answers
                ),
                "student",
                db,
            )
            assert result["xp_earned"] == 50
        else:
            result = quiz.submit_simulado(
                quiz.SimuladoSubmitIn(
                    session_id="generated",
                    total=5,
                    correct=0,
                    xp_earned=999,
                    answers=answers,
                ),
                "student",
                db,
            )
            assert result["xp_earned"] == 25


def test_tampered_receipt_cannot_credit_or_change_totals(store):
    engine, uid = store
    answer = trusted_answer(uid)
    answer["question_id"] = answer["question_id"][:-1] + (
        "0" if answer["question_id"][-1] != "0" else "1"
    )
    with Session(engine) as db:
        with pytest.raises(HTTPException):
            quiz.submit_quiz(
                quiz.QuizSubmitIn(total=1, correct=1, answers=[answer]), "student", db
            )
        assert db.get(models.User, uid).xp == 0
        assert db.scalar(select(func.count(models.QuizStatsEvent.id))) == 0
        assert db.scalar(select(func.count(models.QuizStatsDaily.id))) == 0


def test_failed_receipt_claim_rolls_back_the_whole_new_session(store):
    engine, uid = store
    old = trusted_answer(uid)
    fresh = trusted_answer(uid)
    with Session(engine) as db:
        quiz.submit_quiz(
            quiz.QuizSubmitIn(session_id="original", total=1, correct=1, answers=[old]),
            "student",
            db,
        )
        with pytest.raises(HTTPException):
            quiz.submit_quiz(
                quiz.QuizSubmitIn(
                    session_id="mixed", total=2, correct=2, answers=[fresh, old]
                ),
                "student",
                db,
            )
        assert db.scalar(select(func.count(models.QuizStatsEvent.id))) == 1
        assert db.scalar(select(func.count(models.QuizAnswerCredit.id))) == 1
        assert db.get(models.User, uid).xp == 10
        # Failed claim must not consume the fresh question.
        assert (
            quiz.submit_quiz(
                quiz.QuizSubmitIn(
                    session_id="fresh", total=1, correct=1, answers=[fresh]
                ),
                "student",
                db,
            )["xp_earned"]
            == 10
        )


def test_flashcard_reward_visible_in_stats_but_never_inflates_question_count(
    store, monkeypatch
):
    from app.routers import user

    engine, uid = store
    monkeypatch.setattr(
        user, "_require_user", lambda authorization, db: db.get(models.User, uid)
    )
    with Session(engine) as db:
        body = flashcard.FlashcardReviewIn(
            flashcard_id="local",
            front="Question",
            back="Answer",
            grade="easy",
            reviewed_at=datetime.now(timezone.utc).isoformat(),
        )
        flashcard.review_flashcard(body, "student", db)
        stats = user.get_user_stats("student", db)
        assert stats["total_xp"] == stats["today_xp"] == 5
        assert stats["flashcards_today"] == 1
        assert stats["total_questoes"] == stats["total_acertos"] == 0
