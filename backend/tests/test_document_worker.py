from __future__ import annotations

from collections.abc import Iterator
from datetime import datetime, timezone

from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app import models, services


def _database() -> Iterator[Session]:
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    models.Base.metadata.create_all(engine)
    with Session(engine) as session:
        yield session


def _account(db: Session) -> models.User:
    account = models.User(
        name="Owner",
        login_id="owner",
        email_id="owner@example.com",
        password_hash=services.hash_password("Strong-password-123!"),
    )
    db.add(account)
    db.commit()
    db.refresh(account)
    return account


def test_segment_analyzer_prompt_demands_grounded_page_evidence() -> None:
    from app.document_worker import build_segment_analysis_prompt

    prompt = build_segment_analysis_prompt(
        cargo_title="Analista de Sistemas",
        text="[PAGINA 80]\nBanco de Dados: SQL e normalizacao.",
        page_numbers=(80,),
        segment_index=2,
        segment_total=4,
    )

    assert "Analista de Sistemas" in prompt
    assert "segmento 2 de 4" in prompt.lower()
    assert '"pagina": 80' in prompt
    assert "nao invente" in prompt.lower()
    assert "somente" in prompt.lower()


def test_default_analyzer_prioritizes_gemini_and_limits_response_tokens(
    monkeypatch,
) -> None:
    from app import document_worker
    from app.admin_ai import AiCredentialCandidate

    requested: list[str | None] = []
    output_limits: list[int | None] = []
    candidate = AiCredentialCandidate(
        provider="gemini",
        model="gemini-3.5-flash",
        api_key="server-key",
        key_id=None,
        source="server_env",
    )

    def fake_candidates(_user, _db, *, requested_provider=None):
        requested.append(requested_provider)
        return [candidate]

    def fake_call(
        _db,
        _candidates,
        *,
        system_prompt,
        user_prompt,
        max_output_tokens=None,
    ):
        del system_prompt, user_prompt
        output_limits.append(max_output_tokens)
        return '{"disciplinas":[]}', candidate

    monkeypatch.setattr(document_worker, "build_ai_candidates", fake_candidates)
    monkeypatch.setattr(document_worker, "call_ai_with_fallback", fake_call)

    analyzer = document_worker.build_default_analyzer(object(), object())
    result = analyzer("[PAGINA 1]\nTexto", (1,), 1, 1)

    assert result == {"disciplinas": []}
    assert requested == ["gemini"]
    assert output_limits == [4096]


def test_default_analyzer_rejects_malformed_schema_for_segment_split(
    monkeypatch,
) -> None:
    import pytest

    from app import document_worker
    from app.admin_ai import AiCredentialCandidate
    from app.document_processing import DocumentProcessingError

    candidate = AiCredentialCandidate(
        provider="groq",
        model="llama-test",
        api_key="server-key",
        key_id=None,
        source="server_env",
    )
    monkeypatch.setattr(
        document_worker,
        "build_ai_candidates",
        lambda *_args, **_kwargs: [candidate],
    )
    monkeypatch.setattr(
        document_worker,
        "call_ai_with_fallback",
        lambda *_args, **_kwargs: ("{}", candidate),
    )

    analyzer = document_worker.build_default_analyzer(object(), object())

    with pytest.raises(DocumentProcessingError) as raised:
        analyzer("[PAGINA 29]\nConteudo extenso", (29,), 1, 1)

    assert raised.value.code == "analysis_response_invalid"


def test_process_claimed_job_dispatches_extraction_with_injected_engine() -> None:
    from app.document_worker import process_claimed_job

    db = next(_database())
    owner = _account(db)
    document = models.StudyDocument(
        user_id=owner.id,
        purpose="library",
        file_name="material.pdf",
        content_type="application/pdf",
        size_bytes=10,
        sha256="a" * 64,
        pdf_bytes=b"%PDF-1.7",
        status="extracting",
        progress=0,
    )
    db.add(document)
    db.flush()
    job = models.StudyDocumentJob(
        document_id=document.id,
        user_id=owner.id,
        kind="extract",
        status="running",
        attempt_count=1,
        available_at=datetime.now(timezone.utc),
    )
    db.add(job)
    db.commit()

    process_claimed_job(
        db,
        job,
        page_extractor=lambda _bytes: [
            {
                "page_number": 1,
                "text": "Texto extraido",
                "method": "native",
                "quality": 1,
            }
        ],
    )
    db.refresh(document)
    db.refresh(job)

    assert document.status == "ready"
    assert job.status == "completed"


def test_process_claimed_analysis_uses_factory_for_owner_and_selected_cargo() -> None:
    from app.document_worker import process_claimed_job

    db = next(_database())
    owner = _account(db)
    document = models.StudyDocument(
        user_id=owner.id,
        purpose="study_plan",
        file_name="edital.pdf",
        content_type="application/pdf",
        size_bytes=10,
        sha256="b" * 64,
        pdf_bytes=b"%PDF-1.7",
        status="analyzing",
        progress=60,
        selected_cargo_id="cargo",
        selected_cargo_title="Analista",
    )
    db.add(document)
    db.flush()
    db.add(
        models.StudyDocumentPage(
            document_id=document.id,
            page_number=80,
            text="ANALISTA\nBanco de Dados: SQL.",
            extraction_method="native",
            quality=1,
            text_sha256="c" * 64,
        )
    )
    job = models.StudyDocumentJob(
        document_id=document.id,
        user_id=owner.id,
        kind="analyze",
        status="running",
        attempt_count=1,
        payload={"cargo_id": "cargo", "cargo_title": "Analista"},
        available_at=datetime.now(timezone.utc),
    )
    db.add(job)
    db.commit()
    owners: list[int] = []

    def analyzer_factory(_db: Session, account: models.User):
        owners.append(account.id)
        return lambda _text, pages, _index, _total: {
            "disciplinas": [
                {
                    "nome": "Banco de Dados",
                    "topicos": ["SQL"],
                    "evidencias": [
                        {"pagina": pages[0], "trecho": "Banco de Dados: SQL"}
                    ],
                }
            ]
        }

    process_claimed_job(db, job, analyzer_factory=analyzer_factory)
    db.refresh(document)

    assert owners == [owner.id]
    assert document.status == "ready"
    assert document.analysis_result["disciplinas"][0]["nome"] == "Banco de Dados"


def test_analysis_factory_failure_returns_job_to_retry_queue() -> None:
    from app.document_processing import DocumentProcessingError
    from app.document_worker import process_claimed_job

    db = next(_database())
    owner = _account(db)
    document = models.StudyDocument(
        user_id=owner.id,
        purpose="study_plan",
        file_name="edital.pdf",
        content_type="application/pdf",
        size_bytes=10,
        sha256="d" * 64,
        pdf_bytes=b"%PDF-1.7",
        status="analyzing",
        progress=60,
        selected_cargo_id="cargo",
        selected_cargo_title="Analista",
    )
    db.add(document)
    db.flush()
    db.add(
        models.StudyDocumentPage(
            document_id=document.id,
            page_number=80,
            text="ANALISTA\nBanco de Dados: SQL.",
            extraction_method="native",
            quality=1,
            text_sha256="e" * 64,
        )
    )
    job = models.StudyDocumentJob(
        document_id=document.id,
        user_id=owner.id,
        kind="analyze",
        status="running",
        attempt_count=1,
        max_attempts=3,
        payload={"cargo_id": "cargo", "cargo_title": "Analista"},
        available_at=datetime.now(timezone.utc),
    )
    db.add(job)
    db.commit()

    def unavailable(_db: Session, _account: models.User):
        raise DocumentProcessingError(
            "ai_keys_unavailable",
            "Nenhuma chave ativa.",
            retryable=True,
        )

    process_claimed_job(db, job, analyzer_factory=unavailable)
    db.refresh(job)
    db.refresh(document)

    assert job.status == "retrying"
    assert job.error_code == "ai_keys_unavailable"
    assert document.status == "analyzing"


def test_broken_database_cleanup_cannot_kill_document_worker() -> None:
    from app.document_worker import close_session_safely, rollback_session_safely

    class BrokenSession:
        def rollback(self) -> None:
            raise RuntimeError("connection already closed")

        def close(self) -> None:
            raise RuntimeError("connection already closed")

    session = BrokenSession()

    assert rollback_session_safely(session) is False
    assert close_session_safely(session) is False
