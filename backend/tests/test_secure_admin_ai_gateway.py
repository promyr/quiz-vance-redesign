from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from app import models, services
from app.admin_ai import (
    create_master_key,
    list_masked_master_keys,
    mark_key_failure,
    select_master_key_candidates,
)
from app.ai_gateway import build_ai_candidates, call_ai_with_fallback
from app.ai_provider_config import resolve_model_for_provider
from app.deps import require_admin


@pytest.fixture()
def db() -> Session:
    engine = create_engine("sqlite+pysqlite:///:memory:")
    models.Base.metadata.create_all(engine)
    with Session(engine) as session:
        yield session


def _user(*, login_id: str, role: str = "user") -> models.User:
    return models.User(
        name=login_id.title(),
        login_id=login_id,
        email_id=f"{login_id}@example.com",
        password_hash=services.hash_password("Strong-password-123!"),
        role=role,
    )


def test_require_admin_rejects_regular_user(db: Session) -> None:
    user = _user(login_id="student")
    db.add(user)
    db.commit()

    with pytest.raises(HTTPException) as error:
        require_admin(user)

    assert error.value.status_code == 403


def test_require_admin_accepts_database_role(db: Session) -> None:
    admin = _user(login_id="admin", role="admin")
    db.add(admin)
    db.commit()

    assert require_admin(admin) is admin


def test_master_key_is_encrypted_and_only_masked_metadata_is_returned(
    db: Session,
) -> None:
    admin = _user(login_id="admin", role="admin")
    db.add(admin)
    db.flush()

    row = create_master_key(
        db,
        actor=admin,
        provider="gemini",
        label="Gemini principal",
        api_key="AIza-secret-value-1234",
        priority=10,
    )
    db.commit()

    assert row.secret_encrypted != "AIza-secret-value-1234"
    payload = list_masked_master_keys(db)
    serialized = str(payload)
    assert "AIza-secret-value-1234" not in serialized
    assert payload[0]["masked_key"].endswith("1234")
    assert "secret_encrypted" not in payload[0]
    assert "api_key" not in payload[0]


def test_gateway_skips_blocked_keys_and_orders_healthy_keys(db: Session) -> None:
    admin = _user(login_id="admin", role="admin")
    db.add(admin)
    db.flush()
    blocked = create_master_key(
        db,
        actor=admin,
        provider="gemini",
        label="Bloqueada",
        api_key="blocked-key",
        priority=1,
    )
    healthy = create_master_key(
        db,
        actor=admin,
        provider="gemini",
        label="Saudavel",
        api_key="healthy-key",
        priority=20,
    )
    blocked.blocked_until = datetime.now(timezone.utc) + timedelta(minutes=5)
    db.commit()

    candidates = select_master_key_candidates(db, preferred_provider="gemini")

    assert [candidate.key_id for candidate in candidates] == [healthy.id]
    assert candidates[0].api_key == "healthy-key"


def test_quota_failure_opens_persisted_circuit_breaker(db: Session) -> None:
    admin = _user(login_id="admin", role="admin")
    db.add(admin)
    db.flush()
    row = create_master_key(
        db,
        actor=admin,
        provider="groq",
        label="Groq",
        api_key="gsk-secret",
        priority=10,
    )
    db.commit()

    mark_key_failure(db, row, error_code="quota_exceeded")
    db.commit()

    assert row.health_status == "blocked"
    assert row.failure_count == 1
    assert row.blocked_until is not None
    blocked_until = row.blocked_until
    if blocked_until.tzinfo is None:
        blocked_until = blocked_until.replace(tzinfo=timezone.utc)
    assert blocked_until > datetime.now(timezone.utc)


def test_gateway_uses_server_pool_when_user_has_no_personal_key(db: Session) -> None:
    admin = _user(login_id="admin", role="admin")
    student = _user(login_id="student")
    db.add_all([admin, student])
    db.flush()
    create_master_key(
        db,
        actor=admin,
        provider="gemini",
        label="Servidor",
        api_key="server-key-value",
        priority=1,
    )
    db.commit()

    candidates = build_ai_candidates(
        student,
        db,
        requested_provider="gemini",
    )

    assert candidates[0].source == "server_pool"
    assert candidates[0].api_key == "server-key-value"


def test_gateway_uses_server_environment_key_when_pool_is_empty(
    db: Session,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    student = _user(login_id="student")
    db.add(student)
    db.commit()
    monkeypatch.setenv("GEMINI_API_KEY", "AIza-server-environment-key")

    candidates = build_ai_candidates(student, db, requested_provider="gemini")

    assert candidates[0].source == "server_env"
    assert candidates[0].provider == "gemini"
    assert candidates[0].api_key == "AIza-server-environment-key"


def test_gateway_falls_back_and_persists_failed_key_health(
    db: Session,
) -> None:
    admin = _user(login_id="admin", role="admin")
    student = _user(login_id="student")
    db.add_all([admin, student])
    db.flush()
    first = create_master_key(
        db,
        actor=admin,
        provider="gemini",
        label="Primeira",
        api_key="first-server-key",
        priority=1,
    )
    second = create_master_key(
        db,
        actor=admin,
        provider="groq",
        label="Segunda",
        api_key="second-server-key",
        priority=2,
    )
    db.commit()

    calls: list[str] = []

    def fake_call(
        provider: str, api_key: str, model: str, system: str, prompt: str
    ) -> str:
        del api_key, model, system, prompt
        calls.append(provider)
        if provider == "gemini":
            raise RuntimeError("provider failed")
        return "ok"

    text, selected = call_ai_with_fallback(
        db,
        build_ai_candidates(student, db, requested_provider="gemini"),
        system_prompt="system",
        user_prompt="prompt",
        call=fake_call,
    )
    db.commit()

    assert text == "ok"
    assert selected.key_id == second.id
    assert calls == ["gemini", "groq"]
    db.refresh(first)
    assert first.failure_count == 1


def test_retired_gemini_model_is_not_reused_from_legacy_settings() -> None:
    model = resolve_model_for_provider(
        "gemini",
        stored_model="gemini-2.0-flash",
        stored_provider="gemini",
    )

    assert model == "gemini-3.5-flash"
