from __future__ import annotations

from collections.abc import Iterator

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
