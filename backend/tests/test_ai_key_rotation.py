from __future__ import annotations

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from app import models, services
from app.admin_ai import (
    create_master_key,
    mark_key_success,
    select_master_key_candidates,
)
from app.ai_gateway import build_ai_candidates


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


def test_key_rotation_least_recently_used(db: Session) -> None:
    admin = _user(login_id="admin", role="admin")
    db.add(admin)
    db.flush()

    # Cria 3 chaves do Gemini com mesma prioridade
    k1 = create_master_key(db, actor=admin, provider="gemini", label="Gemini 1", api_key="gemini-key-1", priority=10)
    k2 = create_master_key(db, actor=admin, provider="gemini", label="Gemini 2", api_key="gemini-key-2", priority=10)
    k3 = create_master_key(db, actor=admin, provider="gemini", label="Gemini 3", api_key="gemini-key-3", priority=10)
    db.commit()

    # 1. No início (nenhuma usada), ordem é por ID: k1, k2, k3
    candidates = select_master_key_candidates(db, preferred_provider="gemini")
    assert [c.key_id for c in candidates] == [k1.id, k2.id, k3.id]

    # 2. k1 é usada com sucesso -> vai para o fim da fila!
    mark_key_success(db, k1)
    db.commit()

    candidates = select_master_key_candidates(db, preferred_provider="gemini")
    assert [c.key_id for c in candidates] == [k2.id, k3.id, k1.id]

    # 3. k2 é usada com sucesso -> vai para o fim da fila!
    mark_key_success(db, k2)
    db.commit()

    candidates = select_master_key_candidates(db, preferred_provider="gemini")
    assert [c.key_id for c in candidates] == [k3.id, k1.id, k2.id]


def test_cross_provider_interleaved_rotation(db: Session) -> None:
    admin = _user(login_id="admin", role="admin")
    db.add(admin)
    db.flush()

    g1 = create_master_key(db, actor=admin, provider="gemini", label="Gemini 1", api_key="gemini-test-key-1", priority=10)
    g2 = create_master_key(db, actor=admin, provider="gemini", label="Gemini 2", api_key="gemini-test-key-2", priority=10)
    q1 = create_master_key(db, actor=admin, provider="groq", label="Groq 1", api_key="gsk-test-key-1", priority=10)
    q2 = create_master_key(db, actor=admin, provider="groq", label="Groq 2", api_key="gsk-test-key-2", priority=10)
    db.commit()

    # Sem provedor preferido fixado (modo equilibrado), deve intercalar Gemini e Groq:
    candidates = select_master_key_candidates(db, preferred_provider=None)
    providers = [c.provider for c in candidates]
    assert providers == ["gemini", "groq", "gemini", "groq"]
    assert [c.key_id for c in candidates] == [g1.id, q1.id, g2.id, q2.id]

    # Após g1 ter sucesso, Groq descansou por mais tempo -> próximo topo deve ser Groq (q1)!
    mark_key_success(db, g1)
    db.commit()

    candidates = select_master_key_candidates(db, preferred_provider=None)
    assert candidates[0].provider == "groq"
    assert candidates[0].key_id == q1.id

    # Após q1 ter sucesso, o próximo topo volta a ser Gemini (g2, que ainda não foi usado)!
    mark_key_success(db, q1)
    db.commit()

    candidates = select_master_key_candidates(db, preferred_provider=None)
    assert candidates[0].provider == "gemini"
    assert candidates[0].key_id == g2.id

    # Após g2 ter sucesso, o próximo topo volta a ser Groq (q2, que ainda não foi usado)!
    mark_key_success(db, g2)
    db.commit()

    candidates = select_master_key_candidates(db, preferred_provider=None)
    assert candidates[0].provider == "groq"
    assert candidates[0].key_id == q2.id


def test_study_plan_prefers_gemini_with_groq_fallback(db: Session) -> None:
    admin = _user(login_id="admin", role="admin")
    student = _user(login_id="student", role="user")
    db.add_all([admin, student])
    db.flush()

    g1 = create_master_key(db, actor=admin, provider="gemini", label="Gemini 1", api_key="gemini-test-key-1", priority=10)
    g2 = create_master_key(db, actor=admin, provider="gemini", label="Gemini 2", api_key="gemini-test-key-2", priority=10)
    q1 = create_master_key(db, actor=admin, provider="groq", label="Groq 1", api_key="gsk-test-key-1", priority=10)
    q2 = create_master_key(db, actor=admin, provider="groq", label="Groq 2", api_key="gsk-test-key-2", priority=10)
    db.commit()

    # Quando solicitado especificamente gemini (como no Plano de Estudos):
    candidates = build_ai_candidates(student, db, requested_provider="gemini")
    providers = [c.provider for c in candidates if c.source == "server_pool"]
    
    # Todas as chaves do Gemini devem vir ANTES de qualquer chave do Groq
    assert providers[:2] == ["gemini", "gemini"]
    assert providers[2:] == ["groq", "groq"]
    assert [c.key_id for c in candidates if c.source == "server_pool"] == [g1.id, g2.id, q1.id, q2.id]

    # Se g1 é usada no plano de estudos, g2 vira a primeira, mas AINDA antes do Groq:
    mark_key_success(db, g1)
    db.commit()

    candidates = build_ai_candidates(student, db, requested_provider="gemini")
    pool_candidates = [c for c in candidates if c.source == "server_pool"]
    assert [c.key_id for c in pool_candidates] == [g2.id, g1.id, q1.id, q2.id]


def test_cross_provider_rotation_with_identical_clock(db: Session, monkeypatch) -> None:
    from datetime import datetime, timezone

    from app import admin_ai

    frozen = datetime(2026, 10, 4, 12, tzinfo=timezone.utc)
    monkeypatch.setattr(admin_ai, "_utc_now", lambda: frozen)
    test_cross_provider_interleaved_rotation(db)
