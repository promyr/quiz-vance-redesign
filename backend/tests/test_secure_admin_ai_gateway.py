from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from app import models, services
from app.admin_ai import (
    classify_provider_error,
    create_master_key,
    list_masked_master_keys,
    mark_key_failure,
    provider_error_message,
    provider_retry_after_seconds,
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


def test_gateway_ignores_existing_personal_key(db: Session) -> None:
    admin = _user(login_id="admin", role="admin")
    student = _user(login_id="student")
    db.add_all([admin, student])
    db.flush()
    db.add(
        models.UserSettings(
            user_id=student.id,
            provider="gemini",
            api_key_gemini=services.encrypt_api_key(
                "test-secret-that-is-at-least-32-bytes-long",
                "personal-key-value",
            ),
        )
    )
    create_master_key(
        db,
        actor=admin,
        provider="gemini",
        label="Servidor",
        api_key="server-key-value",
        priority=1,
    )
    db.commit()

    candidates = build_ai_candidates(student, db, requested_provider="gemini")

    assert candidates[0].source == "server_pool"
    assert all(candidate.source != "user" for candidate in candidates)


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


def test_gateway_keeps_environment_key_as_last_resort_after_pool(
    db: Session,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    admin = _user(login_id="admin", role="admin")
    student = _user(login_id="student")
    db.add_all([admin, student])
    db.flush()
    create_master_key(
        db,
        actor=admin,
        provider="gemini",
        label="Servidor",
        api_key="pool-key-value",
        priority=1,
    )
    db.commit()
    monkeypatch.setenv("GEMINI_API_KEY", "AIza-server-environment-key")

    candidates = build_ai_candidates(student, db, requested_provider="gemini")

    assert [candidate.source for candidate in candidates[:2]] == [
        "server_pool",
        "server_env",
    ]


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


def test_gateway_forwards_per_operation_output_budget(db: Session) -> None:
    student = _user(login_id="student")
    db.add(student)
    db.commit()
    candidate = build_ai_candidates(student, db)
    if not candidate:
        from app.admin_ai import AiCredentialCandidate

        candidate = [
            AiCredentialCandidate(
                provider="gemini",
                model="gemini-3.5-flash",
                api_key="server-key",
                key_id=None,
                source="server_env",
            )
        ]
    received: list[int | None] = []

    def fake_call(
        _provider,
        _api_key,
        _model,
        _system,
        _prompt,
        *,
        max_output_tokens=None,
    ):
        received.append(max_output_tokens)
        return "ok"

    text, _selected = call_ai_with_fallback(
        db,
        candidate,
        system_prompt="system",
        user_prompt="prompt",
        max_output_tokens=1500,
        call=fake_call,
    )

    assert text == "ok"
    assert received == [1500]


def test_gateway_fallback_does_not_degrade_key_for_payload_size(
    db: Session,
) -> None:
    from app.admin_ai import AiCredentialCandidate

    admin = _user(login_id="admin", role="admin")
    db.add(admin)
    db.flush()
    row = create_master_key(
        db,
        actor=admin,
        provider="groq",
        label="Groq",
        api_key="gsk-secret",
        priority=1,
    )
    row.health_status = "healthy"
    db.commit()

    class Response:
        status_code = 413

    class TooLarge(RuntimeError):
        response = Response()

    calls = 0

    def fake_call(_provider, _api_key, _model, _system, _prompt):
        nonlocal calls
        calls += 1
        if calls == 1:
            raise TooLarge("payload body omitted")
        return "ok"

    candidates = [
        AiCredentialCandidate(
            provider="groq",
            model="llama-3.3-70b-versatile",
            api_key="gsk-secret",
            key_id=row.id,
            source="server_pool",
        ),
        AiCredentialCandidate(
            provider="gemini",
            model="gemini-3.5-flash",
            api_key="gemini-secret",
            key_id=None,
            source="server_env",
        ),
    ]
    text, _selected = call_ai_with_fallback(
        db,
        candidates,
        system_prompt="system",
        user_prompt="prompt",
        call=fake_call,
    )
    db.refresh(row)

    assert text == "ok"
    assert row.health_status == "healthy"
    assert row.failure_count == 0


def test_payload_too_large_is_not_counted_as_a_key_failure(db: Session) -> None:
    admin = _user(login_id="admin", role="admin")
    db.add(admin)
    db.flush()
    row = create_master_key(
        db,
        actor=admin,
        provider="groq",
        label="Groq",
        api_key="gsk-secret",
        priority=1,
    )
    row.health_status = "healthy"
    db.commit()

    mark_key_failure(db, row, error_code="payload_too_large")
    db.commit()
    db.refresh(row)

    assert row.health_status == "healthy"
    assert row.failure_count == 0
    assert row.blocked_until is None
    assert row.last_error_code is None


def test_provider_error_classification_is_stable_and_user_safe() -> None:
    class Response:
        def __init__(self, status_code: int):
            self.status_code = status_code
            self.headers = {"Retry-After": "90"}

    class ProviderFailure(RuntimeError):
        def __init__(self, status_code: int):
            super().__init__("secret provider response must not leak")
            self.response = Response(status_code)

    assert classify_provider_error(ProviderFailure(413)) == "payload_too_large"
    assert classify_provider_error(ProviderFailure(429)) == "rate_limit"
    assert classify_provider_error(ProviderFailure(503)) == "provider_unavailable"
    assert provider_error_message("invalid_key") == (
        "A chave foi recusada pelo provedor."
    )
    assert provider_error_message("rate_limited") == (
        "O provedor limitou temporariamente as requisicoes."
    )
    assert provider_error_message("provider_unavailable") == (
        "O provedor esta temporariamente indisponivel."
    )
    assert provider_retry_after_seconds(ProviderFailure(429)) == 90


def test_rate_limit_uses_cooldown_without_marking_key_invalid(
    db: Session,
) -> None:
    admin = _user(login_id="admin", role="admin")
    db.add(admin)
    db.flush()
    row = create_master_key(
        db,
        actor=admin,
        provider="gemini",
        label="Gemini",
        api_key="gemini-secret",
        priority=1,
    )
    db.commit()

    before = datetime.now(timezone.utc)
    mark_key_failure(
        db,
        row,
        error_code="rate_limited",
        retry_after_seconds=90,
    )
    db.commit()
    db.refresh(row)

    assert row.health_status == "degraded"
    assert row.last_error_code == "rate_limit"
    assert row.failure_count == 1
    assert row.blocked_until is not None
    blocked_until = row.blocked_until
    if blocked_until.tzinfo is None:
        blocked_until = blocked_until.replace(tzinfo=timezone.utc)
    assert blocked_until >= before + timedelta(seconds=89)


def test_retired_gemini_model_is_not_reused_from_legacy_settings() -> None:
    model = resolve_model_for_provider(
        "gemini",
        stored_model="gemini-2.0-flash",
        stored_provider="gemini",
    )

    assert model == "gemini-3.5-flash"
