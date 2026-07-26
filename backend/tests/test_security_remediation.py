from __future__ import annotations

import hashlib
import hmac
from collections.abc import Iterator

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool
from starlette.requests import Request
from typing_extensions import Self

from app import main, mercadopago, models, services, telegram_bot
from app.database import get_db
from app.routers import admin_ai, user


@pytest.fixture()
def db() -> Iterator[Session]:
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    models.Base.metadata.create_all(engine)
    with Session(engine) as session:
        yield session


def _user(*, login_id: str = "student", role: str = "user") -> models.User:
    return models.User(
        name=login_id.title(),
        login_id=login_id,
        email_id=f"{login_id}@example.com",
        password_hash=services.hash_password("Strong-password-123!"),
        role=role,
    )


def _auth_header(account: models.User) -> dict[str, str]:
    token = services.create_access_token(
        "test-secret-that-is-at-least-32-bytes-long",
        account.id,
        account.email_id,
        account.auth_version,
    )
    return {"Authorization": f"Bearer {token}"}


def test_manual_checkout_confirmation_never_activates_premium(db: Session) -> None:
    account = _user()
    db.add(account)
    db.commit()
    checkout, _ = services.create_checkout_session(
        db, account.id, "premium_30", "manual"
    )

    ok, message, _ = services.confirm_checkout_session(
        db,
        account.id,
        checkout.checkout_id,
        checkout.auth_token,
        "attacker-controlled-id",
        "manual",
    )

    assert ok is False
    assert "verificado" in message.lower()
    assert db.query(models.Payment).count() == 0
    plan = db.query(models.UserPlan).filter_by(user_id=account.id).first()
    assert plan is None or plan.premium_until is None


@pytest.mark.parametrize(
    ("amount_cents", "currency", "plan_code"),
    [
        (1, "BRL", "premium_30"),
        (1990, "USD", "premium_30"),
        (1990, "BRL", "premium_fake"),
    ],
)
def test_verified_payment_must_match_checkout_terms(
    db: Session,
    amount_cents: int,
    currency: str,
    plan_code: str,
) -> None:
    account = _user()
    db.add(account)
    db.commit()
    checkout, _ = services.create_checkout_session(
        db, account.id, "premium_30", "mercadopago"
    )

    ok, message, _ = services.finalize_checkout_payment(
        db,
        checkout,
        provider="mercadopago",
        tx_id=f"payment-{amount_cents}-{currency}-{plan_code}",
        amount_cents=amount_cents,
        currency=currency,
        plan_code=plan_code,
    )

    assert ok is False
    assert "divergente" in message.lower()
    assert db.query(models.Payment).count() == 0


def test_mercadopago_webhook_signature_uses_official_manifest() -> None:
    secret = "webhook-secret"
    data_id = "123456"
    request_id = "request-abc"
    timestamp = "1753430400"
    manifest = f"id:{data_id};request-id:{request_id};ts:{timestamp};"
    digest = hmac.new(secret.encode(), manifest.encode(), hashlib.sha256).hexdigest()

    assert mercadopago.verify_webhook_signature(
        data_id=data_id,
        x_request_id=request_id,
        x_signature=f"ts={timestamp},v1={digest}",
        secret=secret,
    )
    assert not mercadopago.verify_webhook_signature(
        data_id=data_id,
        x_request_id=request_id,
        x_signature=f"ts={timestamp},v1={'0' * 64}",
        secret=secret,
    )
    assert not mercadopago.verify_webhook_signature(
        data_id=data_id,
        x_request_id=request_id,
        x_signature="",
        secret=secret,
    )


def _request(headers: list[tuple[bytes, bytes]]) -> Request:
    return Request(
        {
            "type": "http",
            "method": "POST",
            "path": "/",
            "query_string": b"",
            "headers": headers,
            "client": ("127.0.0.1", 1234),
            "server": ("test", 80),
            "scheme": "http",
        }
    )


def test_telegram_webhook_fails_closed_when_secret_is_missing(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(telegram_bot, "webhook_secret", lambda: "")
    request = _request([])

    assert main._telegram_webhook_secret_ok(request) is False


def test_mercadopago_request_signature_fails_closed_without_secret(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(main, "MP_WEBHOOK_SECRET", "")
    request = _request(
        [
            (b"x-signature", b"ts=1,v1=deadbeef"),
            (b"x-request-id", b"request-id"),
        ]
    )

    assert main._mp_webhook_signature_ok(request, "123") is False


def test_telegram_http_error_never_contains_bot_token(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    token = "123456:super-secret-token"

    class Response:
        def raise_for_status(self) -> None:
            raise RuntimeError(
                f"401 for https://api.telegram.org/bot{token}/sendMessage"
            )

    class Client:
        def __init__(self, **_kwargs: object) -> None:
            pass

        def __enter__(self) -> Self:
            return self

        def __exit__(self, *_args: object) -> None:
            return None

        def post(self, *_args: object, **_kwargs: object) -> Response:
            return Response()

    monkeypatch.setattr(telegram_bot.httpx, "Client", Client)
    client = telegram_bot.TelegramBotClient(token=token)

    with pytest.raises(telegram_bot.TelegramBotError) as error:
        client.request("sendMessage")

    assert token not in str(error.value)
    assert "api.telegram.org" not in str(error.value)


def test_login_id_change_requires_password_and_revokes_old_token(db: Session) -> None:
    account = _user()
    db.add(account)
    db.commit()
    app = FastAPI()
    app.include_router(user.router)
    app.dependency_overrides[get_db] = lambda: db
    client = TestClient(app)
    old_header = _auth_header(account)

    denied = client.post(
        "/user/profile/login-id",
        headers=old_header,
        json={"login_id": "new-login", "current_password": "wrong"},
    )
    changed = client.post(
        "/user/profile/login-id",
        headers=old_header,
        json={
            "login_id": "new-login",
            "current_password": "Strong-password-123!",
        },
    )
    old_session = client.get("/user/profile", headers=old_header)

    assert denied.status_code == 401
    assert changed.status_code == 200
    assert old_session.status_code == 401


def test_admin_key_mutation_requires_current_password(db: Session) -> None:
    admin = _user(login_id="admin", role="admin")
    db.add(admin)
    db.commit()
    app = FastAPI()
    app.include_router(admin_ai.router)
    app.dependency_overrides[get_db] = lambda: db
    client = TestClient(app)
    headers = _auth_header(admin)

    denied = client.post(
        "/admin/ai-keys",
        headers=headers,
        json={
            "provider": "gemini",
            "label": "Principal",
            "api_key": "server-secret-key",
            "priority": 1,
        },
    )
    allowed = client.post(
        "/admin/ai-keys",
        headers={**headers, "X-Admin-Password": "Strong-password-123!"},
        json={
            "provider": "gemini",
            "label": "Principal",
            "api_key": "server-secret-key",
            "priority": 1,
        },
    )

    assert denied.status_code == 401
    assert allowed.status_code == 201


def test_client_cannot_forge_achievement_or_xp(db: Session) -> None:
    account = _user()
    db.add(account)
    db.commit()
    app = FastAPI()
    app.include_router(user.router)
    app.dependency_overrides[get_db] = lambda: db
    client = TestClient(app)

    response = client.post(
        "/user/achievements/unlock",
        headers=_auth_header(account),
        json={
            "achievement_id": "attacker-made-this",
            "title": "Admin",
            "xp_reward": 100_000,
        },
    )

    db.refresh(account)
    assert response.status_code == 422
    assert account.xp == 0
    assert db.query(models.UserAchievement).count() == 0


def test_daily_quota_does_not_consume_past_limit(db: Session) -> None:
    account = _user()
    db.add(account)
    db.commit()

    first = services.consume_daily_limit(db, account.id, "quiz", 1)
    denied = services.consume_daily_limit(db, account.id, "quiz", 1)
    row = db.query(models.UsageDaily).filter_by(user_id=account.id).one()

    assert first == (True, 1)
    assert denied == (False, 1)
    assert row.used_count == 1


def test_access_token_cannot_be_used_as_refresh_token() -> None:
    secret = "session-secret-that-is-at-least-32-bytes"
    access = services.create_access_token(secret, 1, "user@example.com")
    refresh = services.create_refresh_token(secret, 1, "user@example.com")

    assert services.verify_access_token(secret, access) is not None
    assert services.verify_refresh_token(secret, access) is None
    assert services.verify_access_token(secret, refresh) is None
    assert services.verify_refresh_token(secret, refresh) is not None


def test_data_key_rotation_reads_previous_key_and_writes_primary(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    legacy_key = "legacy-encryption-key-that-is-at-least-32-bytes"
    primary_key = "primary-encryption-key-that-is-at-least-32-bytes"
    encrypted_legacy = services.encrypt_api_key(legacy_key, "provider-secret")
    monkeypatch.setenv("DATA_ENCRYPTION_KEY", primary_key)
    monkeypatch.setenv("DATA_ENCRYPTION_PREVIOUS_KEYS", legacy_key)

    assert services.decrypt_api_key("different-session-key", encrypted_legacy) == (
        "provider-secret"
    )
    encrypted_primary = services.encrypt_api_key(
        "different-session-key", "new-provider-secret"
    )
    assert encrypted_primary != encrypted_legacy
    assert services.decrypt_api_key(primary_key, encrypted_primary) == (
        "new-provider-secret"
    )


def test_known_achievement_requires_server_side_progress(db: Session) -> None:
    account = _user()
    db.add(account)
    db.commit()
    app = FastAPI()
    app.include_router(user.router)
    app.dependency_overrides[get_db] = lambda: db
    client = TestClient(app)

    denied = client.post(
        "/user/achievements/unlock",
        headers=_auth_header(account),
        json={
            "achievement_id": "primeira_questao",
            "title": "Forjado",
            "xp_reward": 99_999,
        },
    )
    db.add(
        models.QuizStatsDaily(
            user_id=account.id,
            day_key=services.datetime.now(services.timezone.utc).date(),
            questoes=1,
            acertos=1,
            xp_ganho=10,
        )
    )
    db.commit()
    allowed = client.post(
        "/user/achievements/unlock",
        headers=_auth_header(account),
        json={
            "achievement_id": "primeira_questao",
            "title": "Forjado",
            "xp_reward": 99_999,
        },
    )

    db.refresh(account)
    assert denied.status_code == 409
    assert allowed.status_code == 200
    assert allowed.json()["achievement"]["title"] == "Primeira Questao"
    assert allowed.json()["achievement"]["xp_reward"] == 50
    assert account.xp == 50


def test_security_headers_and_wildcard_cors_are_not_credentialed() -> None:
    client = TestClient(main.app)

    health = client.get("/health")
    preflight = client.options(
        "/health",
        headers={
            "Origin": "https://untrusted.example",
            "Access-Control-Request-Method": "GET",
        },
    )

    assert health.headers["x-content-type-options"] == "nosniff"
    assert health.headers["x-frame-options"] == "DENY"
    assert health.headers["content-security-policy"].startswith("default-src")
    assert preflight.headers.get("access-control-allow-origin") == "*"
    assert "access-control-allow-credentials" not in preflight.headers
