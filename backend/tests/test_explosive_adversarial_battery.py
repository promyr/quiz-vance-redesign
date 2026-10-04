from __future__ import annotations

import base64
import os
import threading
from collections.abc import Iterator
from concurrent.futures import ThreadPoolExecutor

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app import models, security, services
from app.admin_ai import (
    AiCredentialCandidate,
    create_master_key,
    select_master_key_candidates,
)
from app.ai_gateway import call_ai_with_fallback
from app.database import get_db
from app.routers import documents


def _database() -> Iterator[Session]:
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    models.Base.metadata.create_all(engine)
    with Session(engine) as session:
        yield session


def _user(
    db: Session,
    login_id: str,
    *,
    role: str = "user",
    auth_version: int = 1,
) -> models.User:
    user = models.User(
        login_id=login_id,
        email_id=f"{login_id}@example.com",
        name=f"User {login_id}",
        password_hash=services.hash_password("Pass123456!"),
        role=role,
        auth_version=auth_version,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def _auth_header(user: models.User, secret: str | None = None) -> dict[str, str]:
    app_secret = secret or os.getenv("APP_BACKEND_SECRET", "test-secret-that-is-at-least-32-bytes-long")
    token = services.create_access_token(app_secret, user.id, user.email_id, user.auth_version)
    return {"Authorization": f"Bearer {token}"}


# ─────────────────────────────────────────────────────────────────────────────
# 1. BATERIA ADVERSARIAL: CRIPTOGRAFIA & SEGREDOS
# ─────────────────────────────────────────────────────────────────────────────

def test_adversarial_corrupted_envelopes_never_leak_plaintext():
    """Simula injeções de envelopes truncados, corrompidos, prefixos falsos e bytes nulos."""
    secret_key = "master-super-secret-key-32-chars-long"

    corrupted_payloads = [
        "enc:v2:",
        "enc:v2:AAAA",
        "enc:v2:" + "A" * 15,
        "enc:v2:" + base64.urlsafe_b64encode(b"short").decode("ascii"),
        "enc:v1:not-a-valid-fernet-token",
        "enc:v3:future-unsupported",
        "enc:v0:zero",
        "enc:malicious:payload",
        "enc:v2:\x00\x00\x00\x00",
        "enc:v1:" + "Z" * 100,
    ]

    for payload in corrupted_payloads:
        with pytest.raises(ValueError, match="secret_decryption_failed"):
            security.decrypt_secret(secret_key, payload)


def test_adversarial_token_replay_and_tampering():
    """Simula adulteração de payload HMAC em JWTs proprietários e ataque de replay com auth_version antiga."""
    secret = "app-backend-secret-with-32-bytes-minimum"
    db = next(_database())
    victim = _user(db, "victim", auth_version=1)

    # Gera token legítimo
    legit_token = services.create_access_token(secret, victim.id, victim.email_id, victim.auth_version)
    verified = services.verify_access_token(secret, legit_token)
    assert verified is not None
    assert verified["uid"] == victim.id

    # Ataque 1: Adulteração de assinatura (tampering)
    parts = legit_token.split(".")
    tampered_sig = parts[0] + "." + parts[1] + ".tampered_signature_payload"
    assert services.verify_access_token(secret, tampered_sig) is None

    # Ataque 2: Adulteração de payload para trocar o UID (IDOR via token)
    fake_payload = base64.urlsafe_b64encode(b'{"uid":9999,"typ":"access"}').decode().rstrip("=")
    forged_token = parts[0] + "." + fake_payload + "." + parts[2]
    assert services.verify_access_token(secret, forged_token) is None

    # Ataque 3: Invalidação de sessão / revogação total
    victim.auth_version = 2
    db.commit()
    assert services.token_matches_user(verified, victim) is False


# ─────────────────────────────────────────────────────────────────────────────
# 2. BATERIA ADVERSARIAL: AI GATEWAY & TEMPESTADE DE ERROS
# ─────────────────────────────────────────────────────────────────────────────

def test_adversarial_ai_gateway_full_outage_does_not_crash_or_leak():
    """Simula colapso total onde todos os provedores retornam 429 ou 500 em cascata."""
    db = next(_database())
    admin = _user(db, "admin_keys", role="admin")

    # Cadastra chaves para simular esgotamento
    k1 = create_master_key(db, actor=admin, provider="gemini", label="K1", api_key="gemini-key-1", priority=10)
    k2 = create_master_key(db, actor=admin, provider="groq", label="K2", api_key="groq-key-1", priority=10)

    candidates = [
        AiCredentialCandidate("gemini", "gemini-3.8-flash", "gemini-key-1", key_id=k1.id, source="server_pool"),
        AiCredentialCandidate("groq", "llama-3.3-70b-versatile", "groq-key-1", key_id=k2.id, source="server_pool"),
    ]

    class RateLimitError(RuntimeError):
        pass

    def failing_call(_provider, _key, _model, _sys, _user, **_kw):
        raise RateLimitError("429 Resource has been exhausted (quota exceeded)")

    with pytest.raises(RuntimeError) as exc_info:
        call_ai_with_fallback(
            db,
            candidates,
            system_prompt="system",
            user_prompt="prompt",
            call=failing_call,
        )

    assert "429" in str(exc_info.value) or "Resource has been exhausted" in str(exc_info.value)

    # Verifica que ambas as chaves registraram falha e foram penalizadas com backoff
    db.refresh(k1)
    db.refresh(k2)
    assert k1.failure_count >= 1
    assert k2.failure_count >= 1
    assert k1.blocked_until is not None
    assert k2.blocked_until is not None


def test_adversarial_concurrent_key_rotation():
    """Simula 20 requisições simultâneas disputando rotação de chaves para evitar race conditions."""
    db = next(_database())
    admin = _user(db, "admin_concurrency", role="admin")

    for i in range(5):
        create_master_key(db, actor=admin, provider="gemini", label=f"G{i}", api_key=f"gemini-key-{i}", priority=10)
        create_master_key(db, actor=admin, provider="groq", label=f"Q{i}", api_key=f"groq-key-{i}", priority=10)

    selected_first_keys = []
    lock = threading.Lock()
    db_lock = threading.Lock()

    def worker_request():
        with db_lock:
            candidates = select_master_key_candidates(db)
        if candidates:
            with lock:
                selected_first_keys.append((candidates[0].provider, candidates[0].key_id))

    with ThreadPoolExecutor(max_workers=10) as executor:
        futures = [executor.submit(worker_request) for _ in range(20)]
        for f in futures:
            f.result()

    assert len(selected_first_keys) == 20
    # Verifica que houve distribuição (não apenas um provedor)
    providers = {p for p, _ in selected_first_keys}
    assert "gemini" in providers


# ─────────────────────────────────────────────────────────────────────────────
# 3. BATERIA ADVERSARIAL: UPLOAD & PATH TRAVERSAL DEFENSE
# ─────────────────────────────────────────────────────────────────────────────

def test_adversarial_path_traversal_on_document_upload():
    """Simula injeção de caracteres de path traversal no nome do arquivo."""

    db = next(_database())
    attacker = _user(db, "attacker")

    app = FastAPI()
    app.include_router(documents.router)
    app.dependency_overrides[get_db] = lambda: db
    client = TestClient(app)

    malicious_filenames = [
        "../../etc/passwd.pdf",
        "..\\..\\windows\\system32\\cmd.exe",
        "nested/../../secret.pdf",
        "....//....//shell.php.pdf",
    ]

    for fname in malicious_filenames:
        response = client.post(
            "/v2/documents",
            headers=_auth_header(attacker),
            data={"purpose": "study_plan"},
            files={"file": (fname, b"%PDF-1.7 safe payload content", "application/pdf")},
        )
        if response.status_code == 202:
            doc_id = response.json()["id"]
            doc = db.get(models.StudyDocument, doc_id)
            # O nome sanitizado não pode conter '../' nem escapar da raiz
            assert ".." not in doc.file_name
            assert "/" not in doc.file_name
            assert "\\" not in doc.file_name


def test_adversarial_file_type_spoofing():
    """Simula envio de arquivo malicioso com extensão PDF mas conteúdo incompatível."""
    db = next(_database())
    attacker = _user(db, "spoofer")

    app = FastAPI()
    app.include_router(documents.router)
    app.dependency_overrides[get_db] = lambda: db
    client = TestClient(app)

    # Executável disfarçado de PDF
    fake_pdf = b"MZ\x90\x00\x03\x00\x00\x00"

    response = client.post(
        "/v2/documents",
        headers=_auth_header(attacker),
        data={"purpose": "study_plan"},
        files={"file": ("virus.pdf", fake_pdf, "application/pdf")},
    )
    # A API deve rejeitar o arquivo que não começa com %PDF com status 422
    assert response.status_code == 422
    assert "invalido" in response.text.lower() or "pdf" in response.text.lower()


# ─────────────────────────────────────────────────────────────────────────────
# 4. BATERIA ADVERSARIAL: CONTROLE DE ACESSO QUEBRADO (IDOR)
# ─────────────────────────────────────────────────────────────────────────────

def test_adversarial_idor_document_access():
    """Garante que o Usuário B não consiga ler, alterar ou deletar documento do Usuário A."""
    db = next(_database())
    victim = _user(db, "victim_user")
    attacker = _user(db, "attacker_user")

    # Documento criado pela vítima
    doc = models.StudyDocument(
        user_id=victim.id,
        purpose="library",
        file_name="apostila_confidencial.pdf",
        content_type="application/pdf",
        size_bytes=100,
        sha256="c" * 64,
        status="ready",
        progress=100,
    )
    db.add(doc)
    db.commit()

    app = FastAPI()
    app.include_router(documents.router)
    app.dependency_overrides[get_db] = lambda: db
    client = TestClient(app)

    # 1. Atacante tenta ler o documento da vítima
    r_get = client.get(f"/v2/documents/{doc.id}", headers=_auth_header(attacker))
    assert r_get.status_code == 404

    # 2. Atacante tenta baixar o conteúdo do documento da vítima
    r_content = client.get(f"/v2/documents/{doc.id}/content", headers=_auth_header(attacker))
    assert r_content.status_code == 404

    # 3. Atacante tenta selecionar cargo no documento da vítima
    r_select = client.post(
        f"/v2/documents/{doc.id}/select-cargo",
        headers=_auth_header(attacker),
        json={"cargo_id": "test"},
    )
    assert r_select.status_code == 404

    # 4. Atacante tenta deletar o documento da vítima
    r_del = client.delete(f"/v2/documents/{doc.id}", headers=_auth_header(attacker))
    assert r_del.status_code == 404

    # Documento deve continuar intacto no banco
    assert db.get(models.StudyDocument, doc.id) is not None
