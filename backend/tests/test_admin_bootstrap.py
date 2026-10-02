from __future__ import annotations

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app import main, models, services


def test_configured_admin_becomes_the_only_admin(monkeypatch) -> None:
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    models.Base.metadata.create_all(engine)
    test_session = sessionmaker(bind=engine, expire_on_commit=False)
    db = test_session()
    configured = models.User(
        name="Configured Admin",
        login_id="promyr",
        email_id="promyr@example.com",
        password_hash=services.hash_password("Strong-password-123!"),
        role="user",
        auth_version=4,
    )
    former_admin = models.User(
        name="Former Admin",
        login_id="legacy-admin",
        email_id="legacy-admin@example.com",
        password_hash=services.hash_password("Strong-password-123!"),
        role="admin",
        auth_version=7,
    )
    db.add_all([configured, former_admin])
    db.commit()

    monkeypatch.setattr(main, "ADMIN_LOGIN_ID", "promyr")
    monkeypatch.setattr(main, "SessionLocal", lambda: db)

    main._promote_configured_admin()

    assert configured.role == "admin"
    assert configured.auth_version == 5
    assert former_admin.role == "user"
    assert former_admin.auth_version == 8
    assert db.query(models.User).filter(models.User.role == "admin").count() == 1

    db.close()
