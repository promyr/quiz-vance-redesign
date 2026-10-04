from __future__ import annotations

from collections.abc import Iterator
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app import models, services
from app.database import get_db


def _database() -> Iterator[Session]:
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    models.Base.metadata.create_all(engine)
    with Session(engine) as session:
        yield session


def _account(db: Session, login_id: str) -> models.User:
    account = models.User(
        name=login_id.title(),
        login_id=login_id,
        email_id=f"{login_id}@example.com",
        password_hash=services.hash_password("Strong-password-123!"),
    )
    db.add(account)
    db.commit()
    db.refresh(account)
    return account


def _headers(account: models.User) -> dict[str, str]:
    token = services.create_access_token(
        "test-secret-that-is-at-least-32-bytes-long",
        account.id,
        account.email_id,
        account.auth_version,
    )
    return {"Authorization": f"Bearer {token}"}


def _client(db: Session) -> TestClient:
    from app.routers import documents

    app = FastAPI()
    app.include_router(documents.router)
    app.dependency_overrides[get_db] = lambda: db
    return TestClient(app)


def test_upload_storage_outage_is_safe_and_does_not_create_job(monkeypatch, tmp_path):
    root = tmp_path / "storage"
    root.write_bytes(b"not a directory")
    monkeypatch.setenv("STUDY_DOCUMENT_STORAGE_ROOT", str(root))
    db = next(_database())
    owner = _account(db, "storageowner")
    response = _client(db).post(
        "/v2/documents", headers=_headers(owner),
        data={"purpose": "library"},
        files={"file": ("book.pdf", b"%PDF-1.7", "application/pdf")},
    )
    assert response.status_code == 503
    assert str(tmp_path) not in response.text
    assert db.query(models.StudyDocument).count() == 0
    assert db.query(models.StudyDocumentJob).count() == 0


def test_upload_creates_private_document_and_durable_extraction_job(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    monkeypatch.setenv("STUDY_DOCUMENT_STORAGE_ROOT", str(tmp_path))
    db = next(_database())
    owner = _account(db, "owner")
    client = _client(db)

    denied = client.post(
        "/v2/documents",
        data={"purpose": "study_plan"},
        files={"file": ("edital.pdf", b"%PDF-1.7\nfake", "application/pdf")},
    )
    response = client.post(
        "/v2/documents",
        headers=_headers(owner),
        data={"purpose": "study_plan"},
        files={"file": ("edital.pdf", b"%PDF-1.7\nfake", "application/pdf")},
    )

    assert denied.status_code == 401
    assert response.status_code == 201
    payload = response.json()
    assert payload["file_name"] == "edital.pdf"
    assert payload["status"] == "extracting"
    assert payload["purpose"] == "study_plan"
    document = db.get(models.StudyDocument, payload["id"])
    assert document is not None
    assert document.user_id == owner.id
    assert document.pdf_bytes is None
    assert document.storage_key
    stored_path = tmp_path / str(document.storage_key)
    assert stored_path.read_bytes() == b"%PDF-1.7\nfake"
    job = (
        db.query(models.StudyDocumentJob)
        .filter(models.StudyDocumentJob.document_id == document.id)
        .one()
    )
    assert job.kind == "extract"
    assert job.status == "queued"


def test_list_get_and_content_never_leak_another_users_document() -> None:
    db = next(_database())
    owner = _account(db, "owner")
    stranger = _account(db, "stranger")
    document = models.StudyDocument(
        user_id=owner.id,
        purpose="library",
        file_name="apostila.pdf",
        content_type="application/pdf",
        size_bytes=12,
        sha256="a" * 64,
        pdf_bytes=b"%PDF-1.7",
        status="ready",
        progress=100,
        extracted_text="Conteudo privado",
    )
    db.add(document)
    db.commit()
    client = _client(db)

    owner_list = client.get("/v2/documents", headers=_headers(owner))
    stranger_list = client.get("/v2/documents", headers=_headers(stranger))
    stranger_get = client.get(
        f"/v2/documents/{document.id}",
        headers=_headers(stranger),
    )
    stranger_content = client.get(
        f"/v2/documents/{document.id}/content",
        headers=_headers(stranger),
    )

    assert [item["id"] for item in owner_list.json()["items"]] == [document.id]
    assert stranger_list.json()["items"] == []
    assert stranger_get.status_code == 404
    assert stranger_content.status_code == 404


def test_select_cargo_queues_analysis_job_using_extracted_cargo() -> None:
    db = next(_database())
    owner = _account(db, "owner")
    document = models.StudyDocument(
        user_id=owner.id,
        purpose="study_plan",
        file_name="edital.pdf",
        content_type="application/pdf",
        size_bytes=12,
        sha256="a" * 64,
        pdf_bytes=b"%PDF-1.7",
        status="awaiting_selection",
        progress=55,
        cargos=[
            {"id": "cargo-1", "title": "Tecnico", "page_number": 5},
            {"id": "cargo-2", "title": "Analista", "page_number": 80},
        ],
    )
    db.add(document)
    db.commit()
    client = _client(db)

    invalid = client.post(
        f"/v2/documents/{document.id}/select-cargo",
        headers=_headers(owner),
        json={"cargo_id": "nao-existe"},
    )
    response = client.post(
        f"/v2/documents/{document.id}/select-cargo",
        headers=_headers(owner),
        json={"cargo_id": "cargo-2"},
    )

    assert invalid.status_code == 422
    assert response.status_code == 202
    assert response.json()["status"] == "analyzing"
    db.refresh(document)
    assert document.selected_cargo_title == "Analista"
    job = (
        db.query(models.StudyDocumentJob)
        .filter(
            models.StudyDocumentJob.document_id == document.id,
            models.StudyDocumentJob.kind == "analyze",
        )
        .one()
    )
    assert job.payload == {"cargo_id": "cargo-2", "cargo_title": "Analista"}


def test_delete_removes_private_pdf_pages_and_jobs() -> None:
    db = next(_database())
    owner = _account(db, "owner")
    document = models.StudyDocument(
        user_id=owner.id,
        purpose="library",
        file_name="apostila.pdf",
        content_type="application/pdf",
        size_bytes=12,
        sha256="a" * 64,
        pdf_bytes=b"%PDF-1.7",
        status="ready",
        progress=100,
    )
    db.add(document)
    db.flush()
    db.add(
        models.StudyDocumentPage(
            document_id=document.id,
            page_number=1,
            text="texto",
            extraction_method="native",
            quality=1,
            text_sha256="b" * 64,
        )
    )
    db.add(
        models.StudyDocumentJob(
            document_id=document.id,
            user_id=owner.id,
            kind="extract",
            status="completed",
        )
    )
    db.commit()
    document_id = document.id
    client = _client(db)

    response = client.delete(
        f"/v2/documents/{document_id}",
        headers=_headers(owner),
    )

    assert response.status_code == 204
    assert db.get(models.StudyDocument, document_id) is None
    assert (
        db.query(models.StudyDocumentPage)
        .filter(models.StudyDocumentPage.document_id == document_id)
        .count()
        == 0
    )
    assert (
        db.query(models.StudyDocumentJob)
        .filter(models.StudyDocumentJob.document_id == document_id)
        .count()
        == 0
    )


@pytest.mark.parametrize("selected,expected_status", [("one", 202), ("two", 409)])
@pytest.mark.parametrize("job_status", ["queued", "running", "retrying"])
def test_select_cargo_preserves_active_worker(selected, expected_status, job_status):
    db = next(_database())
    owner = _account(db, "activeowner")
    document = models.StudyDocument(
        user_id=owner.id, purpose="study_plan", file_name="notice.pdf",
        content_type="application/pdf", size_bytes=12, sha256="a" * 64,
        status="analyzing", progress=78,
        cargos=[{"id": "one", "title": "Tecnico"}, {"id": "two", "title": "Analista"}],
        selected_cargo_id="one", selected_cargo_title="Tecnico",
    )
    db.add(document)
    db.flush()
    job = models.StudyDocumentJob(
        document_id=document.id, user_id=owner.id, kind="analyze",
        status=job_status, progress=50, locked_by="worker-1",
        payload={"cargo_id": "one", "cargo_title": "Tecnico"},
        result={"checkpoints": {"segment": {"done": True}}},
    )
    db.add(job)
    db.commit()
    response = _client(db).post(
        f"/v2/documents/{document.id}/select-cargo",
        headers=_headers(owner), json={"cargo_id": selected},
    )
    assert response.status_code == expected_status
    db.refresh(job)
    db.refresh(document)
    assert job.status == job_status
    assert job.locked_by == "worker-1"
    assert job.payload["cargo_id"] == "one"
    assert job.result["checkpoints"]["segment"]["done"] is True
    assert document.progress == 78
    assert document.selected_cargo_id == "one"
    assert db.query(models.StudyDocumentJob).count() == 1


def test_retry_analysis_reuses_extracted_pages_and_is_idempotent() -> None:
    db = next(_database())
    owner = _account(db, "owner")
    stranger = _account(db, "stranger")
    document = models.StudyDocument(
        user_id=owner.id,
        purpose="study_plan",
        file_name="edital.pdf",
        content_type="application/pdf",
        size_bytes=12,
        sha256="c" * 64,
        status="failed",
        progress=62,
        page_count=1,
        cargos=[{"id": "cargo-1", "title": "Analista"}],
        selected_cargo_id="cargo-1",
        selected_cargo_title="Analista",
        error_code="provider_unavailable",
        error_message="O provedor esta temporariamente indisponivel.",
    )
    db.add(document)
    db.flush()
    db.add(
        models.StudyDocumentPage(
            document_id=document.id,
            page_number=1,
            text="ANALISTA\nBanco de Dados: SQL.",
            extraction_method="native",
            quality=1,
            text_sha256="d" * 64,
        )
    )
    job = models.StudyDocumentJob(
        document_id=document.id,
        user_id=owner.id,
        kind="analyze",
        status="failed",
        progress=20,
        attempt_count=3,
        payload={"cargo_id": "cargo-1", "cargo_title": "Analista"},
        result={"checkpoints": {"hash": {"partial": {"disciplinas": []}}}},
        error_code="provider_unavailable",
        error_message="Falhou.",
    )
    db.add(job)
    db.commit()
    client = _client(db)

    before = client.get(
        f"/v2/documents/{document.id}",
        headers=_headers(owner),
    )
    denied = client.post(
        f"/v2/documents/{document.id}/retry-analysis",
        headers=_headers(stranger),
    )
    first = client.post(
        f"/v2/documents/{document.id}/retry-analysis",
        headers=_headers(owner),
    )
    second = client.post(
        f"/v2/documents/{document.id}/retry-analysis",
        headers=_headers(owner),
    )

    assert before.json()["can_retry"] is True
    assert denied.status_code == 404
    assert first.status_code == 202
    assert second.status_code == 202
    assert first.json()["status"] == "analyzing"
    assert first.json()["can_retry"] is False
    assert (
        db.query(models.StudyDocumentJob)
        .filter(
            models.StudyDocumentJob.document_id == document.id,
            models.StudyDocumentJob.kind == "analyze",
        )
        .count()
        == 1
    )
    db.refresh(job)
    assert job.status == "queued"
    assert job.attempt_count == 0
    assert "checkpoints" in job.result


def test_production_app_exposes_versioned_document_routes() -> None:
    from app.main import app

    paths = app.openapi()["paths"]
    assert "/v2/documents" in paths and "post" in paths["/v2/documents"]
    assert (
        "/v2/documents/{document_id}/select-cargo" in paths
        and "post" in paths["/v2/documents/{document_id}/select-cargo"]
    )
    assert (
        "/v2/documents/{document_id}/retry-analysis" in paths
        and "post" in paths["/v2/documents/{document_id}/retry-analysis"]
    )


def test_review_without_discovered_cargos_accepts_manual_title():
    db = next(_database())
    owner = _account(db, "manualreview")
    document = models.StudyDocument(user_id=owner.id, purpose="study_plan",
        file_name="edital.pdf", content_type="application/pdf", size_bytes=12,
        sha256="a" * 64, status="needs_review", progress=55, cargos=[])
    db.add(document)
    db.flush()
    db.add(models.StudyDocumentPage(document_id=document.id, page_number=1,
        text="Conteudo programatico: Portugues", text_sha256="b" * 64))
    db.commit()
    response = _client(db).post(f"/v2/documents/{document.id}/select-cargo",
        headers=_headers(owner), json={"cargo_id": "manual", "cargo_title": "  Analista  "})
    assert response.status_code == 202
    db.refresh(document)
    assert document.selected_cargo_title == "Analista"
    assert document.status == "analyzing"


@pytest.mark.parametrize("status,with_pages,title", [
    ("extracting", True, "Analista"),
    ("needs_review", False, "Analista"),
    ("needs_review", True, "   "),
])
def test_manual_review_rejects_incomplete_extraction_or_empty_title(status, with_pages, title):
    db = next(_database())
    owner = _account(db, "reviewguard")
    document = models.StudyDocument(user_id=owner.id, purpose="study_plan",
        file_name="edital.pdf", content_type="application/pdf", size_bytes=12,
        sha256="a" * 64, status=status, progress=55, cargos=[])
    db.add(document)
    db.flush()
    if with_pages:
        db.add(models.StudyDocumentPage(document_id=document.id, page_number=1,
            text="Conteudo programatico", text_sha256="b" * 64))
    db.commit()
    response = _client(db).post(f"/v2/documents/{document.id}/select-cargo",
        headers=_headers(owner), json={"cargo_id": "manual", "cargo_title": title})
    assert response.status_code == 422
    assert db.query(models.StudyDocumentJob).count() == 0
