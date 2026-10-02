from __future__ import annotations

import base64
from collections.abc import Iterator

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app import models, services
from app.admin_ai import create_master_key
from app.database import get_db
from app.routers import admin_ai


def _test_app() -> tuple[TestClient, Session, models.User, models.User]:
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    models.Base.metadata.create_all(engine)
    db = Session(engine)
    admin = models.User(
        name="Admin",
        login_id="admin",
        email_id="admin@example.com",
        password_hash=services.hash_password("Strong-password-123!"),
        role="admin",
    )
    user = models.User(
        name="Student",
        login_id="student",
        email_id="student@example.com",
        password_hash=services.hash_password("Strong-password-123!"),
        role="user",
    )
    db.add_all([admin, user])
    db.commit()

    app = FastAPI()
    app.include_router(admin_ai.router)

    def override_db() -> Iterator[Session]:
        yield db

    app.dependency_overrides[get_db] = override_db
    return TestClient(app), db, admin, user


def _auth_header(user: models.User) -> dict[str, str]:
    token = services.create_access_token(
        "test-secret-that-is-at-least-32-bytes-long",
        user.id,
        user.email_id,
        user.auth_version,
    )
    return {"Authorization": f"Bearer {token}"}


def test_regular_user_cannot_list_server_keys() -> None:
    client, db, _admin, user = _test_app()
    try:
        response = client.get("/admin/ai-keys", headers=_auth_header(user))
        assert response.status_code == 403
    finally:
        client.close()
        db.close()


def test_admin_api_never_returns_plaintext_secret() -> None:
    client, db, admin, _user = _test_app()
    try:
        create_master_key(
            db,
            actor=admin,
            provider="gemini",
            label="Principal",
            api_key="AIza-plain-secret-9876",
            priority=1,
        )
        db.commit()

        response = client.get("/admin/ai-keys", headers=_auth_header(admin))

        assert response.status_code == 200
        body = response.json()
        assert body["keys"][0]["masked_key"].endswith("9876")
        assert "AIza-plain-secret-9876" not in response.text
        assert "secret_encrypted" not in response.text
    finally:
        client.close()
        db.close()


def _enroll_biometric(
    client: TestClient,
    admin: models.User,
) -> tuple[Ed25519PrivateKey, str]:
    private_key = Ed25519PrivateKey.generate()
    public_key = private_key.public_key().public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )
    credential_id = "android-test-device"
    response = client.post(
        "/admin/biometric-credentials",
        headers={
            **_auth_header(admin),
            "X-Admin-Password": "Strong-password-123!",
        },
        json={
            "credential_id": credential_id,
            "public_key": base64.urlsafe_b64encode(public_key)
            .decode("ascii")
            .rstrip("="),
            "device_name": "Pixel test",
            "platform": "android",
        },
    )
    assert response.status_code == 201, response.text
    return private_key, credential_id


def _biometric_step_up(
    client: TestClient,
    admin: models.User,
    private_key: Ed25519PrivateKey,
    credential_id: str,
    *,
    scope: str,
) -> str:
    challenge_response = client.post(
        "/admin/biometric-challenges",
        headers=_auth_header(admin),
        json={"credential_id": credential_id, "scope": scope},
    )
    assert challenge_response.status_code == 201, challenge_response.text
    challenge = challenge_response.json()
    challenge_bytes = base64.urlsafe_b64decode(
        challenge["challenge"] + "=" * (-len(challenge["challenge"]) % 4)
    )
    signature = private_key.sign(challenge_bytes)
    verify_response = client.post(
        "/admin/biometric-challenges/verify",
        headers=_auth_header(admin),
        json={
            "challenge_id": challenge["challenge_id"],
            "credential_id": credential_id,
            "signature": base64.urlsafe_b64encode(signature)
            .decode("ascii")
            .rstrip("="),
        },
    )
    assert verify_response.status_code == 200, verify_response.text
    return str(verify_response.json()["step_up_token"])


def test_biometric_step_up_authorizes_exactly_one_admin_action() -> None:
    client, db, admin, _user = _test_app()
    try:
        private_key, credential_id = _enroll_biometric(client, admin)
        step_up_token = _biometric_step_up(
            client,
            admin,
            private_key,
            credential_id,
            scope="ai_key.create",
        )
        payload = {
            "provider": "gemini",
            "label": "Biometric",
            "api_key": "AIza-biometric-test-secret",
            "priority": 1,
        }
        first = client.post(
            "/admin/ai-keys",
            headers={
                **_auth_header(admin),
                "X-Admin-Step-Up": step_up_token,
            },
            json=payload,
        )
        replay = client.post(
            "/admin/ai-keys",
            headers={
                **_auth_header(admin),
                "X-Admin-Step-Up": step_up_token,
            },
            json={**payload, "label": "Replay"},
        )

        assert first.status_code == 201, first.text
        assert replay.status_code == 401
        assert "confirme" in replay.json()["detail"].lower()
    finally:
        client.close()
        db.close()


def test_biometric_step_up_cannot_be_used_for_another_scope() -> None:
    client, db, admin, _user = _test_app()
    try:
        private_key, credential_id = _enroll_biometric(client, admin)
        step_up_token = _biometric_step_up(
            client,
            admin,
            private_key,
            credential_id,
            scope="ai_key.delete",
        )
        response = client.post(
            "/admin/ai-keys",
            headers={
                **_auth_header(admin),
                "X-Admin-Step-Up": step_up_token,
            },
            json={
                "provider": "gemini",
                "label": "Wrong scope",
                "api_key": "AIza-wrong-scope-secret",
            },
        )

        assert response.status_code == 401
    finally:
        client.close()
        db.close()


def test_biometric_challenge_rejects_invalid_signature() -> None:
    client, db, admin, _user = _test_app()
    try:
        _private_key, credential_id = _enroll_biometric(client, admin)
        challenge_response = client.post(
            "/admin/biometric-challenges",
            headers=_auth_header(admin),
            json={"credential_id": credential_id, "scope": "ai_key.test"},
        )
        challenge = challenge_response.json()
        invalid_signature = Ed25519PrivateKey.generate().sign(b"wrong challenge")

        response = client.post(
            "/admin/biometric-challenges/verify",
            headers=_auth_header(admin),
            json={
                "challenge_id": challenge["challenge_id"],
                "credential_id": credential_id,
                "signature": base64.urlsafe_b64encode(invalid_signature)
                .decode("ascii")
                .rstrip("="),
            },
        )

        assert response.status_code == 401
        assert "biometr" in response.json()["detail"].lower()
    finally:
        client.close()
        db.close()


def test_biometric_reorder_uses_one_grant_for_the_whole_operation() -> None:
    client, db, admin, _user = _test_app()
    try:
        first = create_master_key(
            db,
            actor=admin,
            provider="gemini",
            label="First",
            api_key="AIza-first-secret",
            priority=10,
        )
        second = create_master_key(
            db,
            actor=admin,
            provider="groq",
            label="Second",
            api_key="gsk_second-secret",
            priority=20,
        )
        db.commit()
        private_key, credential_id = _enroll_biometric(client, admin)
        step_up_token = _biometric_step_up(
            client,
            admin,
            private_key,
            credential_id,
            scope="ai_key.reorder",
        )

        response = client.post(
            "/admin/ai-keys/reorder",
            headers={
                **_auth_header(admin),
                "X-Admin-Step-Up": step_up_token,
            },
            json={
                "keys": [
                    {"id": second.id, "priority": 10},
                    {"id": first.id, "priority": 20},
                ]
            },
        )

        assert response.status_code == 200, response.text
        db.refresh(first)
        db.refresh(second)
        assert second.priority == 10
        assert first.priority == 20
    finally:
        client.close()
        db.close()
