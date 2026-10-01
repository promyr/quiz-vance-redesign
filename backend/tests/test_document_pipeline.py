from __future__ import annotations

from collections.abc import Iterator
from datetime import datetime, timezone
from io import BytesIO

import pytest
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


def _account(db: Session, login_id: str = "owner") -> models.User:
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


def test_pdf_validator_accepts_pdf_signature_after_mobile_provider_prefix() -> None:
    from app.document_processing import validate_pdf_upload

    metadata = validate_pdf_upload(
        file_name="edital.PDF",
        content_type="application/pdf",
        content=b"\x00mobile-prefix%PDF-1.7\nbody",
        max_bytes=1024,
    )

    assert metadata.file_name == "edital.PDF"
    assert metadata.size_bytes == 27
    assert metadata.sha256


def test_real_pdf_engine_extracts_page_text_without_global_truncation() -> None:
    from pypdf import PdfWriter
    from pypdf.generic import (
        DecodedStreamObject,
        DictionaryObject,
        NameObject,
    )

    from app.document_processing import extract_pdf_pages

    writer = PdfWriter()
    page = writer.add_blank_page(width=595, height=842)
    font = DictionaryObject(
        {
            NameObject("/Type"): NameObject("/Font"),
            NameObject("/Subtype"): NameObject("/Type1"),
            NameObject("/BaseFont"): NameObject("/Helvetica"),
        }
    )
    resources = DictionaryObject(
        {
            NameObject("/Font"): DictionaryObject(
                {NameObject("/F1"): writer._add_object(font)}
            )
        }
    )
    content = DecodedStreamObject()
    content.set_data(
        b"BT /F1 12 Tf 72 770 Td "
        b"(ANALISTA DE SISTEMAS - Banco de Dados SQL) Tj ET"
    )
    page[NameObject("/Resources")] = resources
    page[NameObject("/Contents")] = writer._add_object(content)
    buffer = BytesIO()
    writer.write(buffer)

    pages = extract_pdf_pages(buffer.getvalue())

    assert len(pages) == 1
    assert "Banco de Dados SQL" in pages[0]["text"]
    assert pages[0]["method"] == "native"


@pytest.mark.parametrize(
    ("file_name", "content_type", "content", "message"),
    [
        ("edital.txt", "text/plain", b"%PDF-1.7", "somente pdf"),
        ("edital.pdf", "application/pdf", b"not-a-pdf", "pdf invalido"),
        ("edital.pdf", "application/pdf", b"%PDF-1.7" + b"x" * 20, "excede"),
    ],
)
def test_pdf_validator_rejects_invalid_type_signature_and_size(
    file_name: str,
    content_type: str,
    content: bytes,
    message: str,
) -> None:
    from app.document_processing import DocumentValidationError, validate_pdf_upload

    with pytest.raises(DocumentValidationError, match=message):
        validate_pdf_upload(
            file_name=file_name,
            content_type=content_type,
            content=content,
            max_bytes=16,
        )


def test_analysis_windows_keep_late_content_and_page_evidence() -> None:
    from app.document_processing import build_analysis_windows

    pages = [
        {"page_number": page, "text": "Informacoes gerais " * 400}
        for page in range(1, 80)
    ]
    pages.extend(
        [
            {
                "page_number": 80,
                "text": (
                    "CARGO 42 - ANALISTA DE TECNOLOGIA\n"
                    "CONHECIMENTOS ESPECIFICOS\n"
                    "Banco de Dados: SQL, normalizacao e transacoes."
                ),
            },
            {
                "page_number": 81,
                "text": (
                    "ANALISTA DE TECNOLOGIA\n"
                    "Seguranca da Informacao: criptografia e gestao de riscos."
                ),
            },
        ]
    )

    windows = build_analysis_windows(
        pages,
        cargo_title="Analista de Tecnologia",
        max_chars=2500,
    )

    combined = "\n".join(window.text for window in windows)
    evidence_pages = {
        page for window in windows for page in window.page_numbers
    }
    assert "Banco de Dados" in combined
    assert "Seguranca da Informacao" in combined
    assert {80, 81}.issubset(evidence_pages)
    assert all(len(window.text) <= 2500 for window in windows)


def test_analysis_windows_default_to_safe_eight_thousand_characters() -> None:
    from app.document_processing import build_analysis_windows

    windows = build_analysis_windows(
        [
            {
                "page_number": 7,
                "text": "ANALISTA\nCONTEUDO PROGRAMATICO\n" + ("x" * 20_000),
            }
        ],
        cargo_title="Analista",
    )

    assert len(windows) >= 3
    assert all(len(window.text) <= 8_000 for window in windows)


def test_analysis_windows_match_short_profile_heading_from_full_cargo_title() -> None:
    from app.document_processing import build_analysis_windows

    pages = [
        {
            "page_number": 26,
            "text": "ANEXO I - CONTEUDO PROGRAMATICO\nPERFIL 1: NEGOCIOS",
        },
        {
            "page_number": 27,
            "text": "PERFIL 2: ARQUITETURA\nConteudo de outro perfil.",
        },
        {
            "page_number": 28,
            "text": "Continuidade do perfil anterior.",
        },
        {
            "page_number": 29,
            "text": (
                "PERFIL 3: DESENVOLVIMENTO DE SOFTWARE\n"
                "ENGENHARIA DE SOFTWARE: requisitos, testes e arquitetura."
            ),
        },
        {
            "page_number": 30,
            "text": "PERFIL 4: INTELIGENCIA DA INFORMACAO",
        },
    ]

    windows = build_analysis_windows(
        pages,
        cargo_title=(
            "ANALISTA DE TECNOLOGIA DA INFORMACAO - "
            "PERFIL: 3. DESENVOLVIMENTO DE SOFTWARE"
        ),
    )

    combined = "\n".join(window.text for window in windows)
    evidence_pages = {
        page for window in windows for page in window.page_numbers
    }
    assert "ENGENHARIA DE SOFTWARE" in combined
    assert 29 in evidence_pages


def test_metadata_discovery_understands_perfil_and_especialidade_labels() -> None:
    from app.document_processing import discover_notice_metadata

    cargos, exam_date = discover_notice_metadata(
        [
            {
                "page_number": 12,
                "text": (
                    "PERFIL PROFISSIONAL: ANALISTA DE TECNOLOGIA DA INFORMACAO\n"
                    "ESPECIALIDADE - DESENVOLVIMENTO DE SISTEMAS\n"
                    "Realizacao da prova objetiva: 15/08/2027"
                ),
            }
        ]
    )

    assert [cargo["title"] for cargo in cargos] == [
        "ANALISTA DE TECNOLOGIA DA INFORMACAO",
        "DESENVOLVIMENTO DE SISTEMAS",
    ]
    assert exam_date == "2027-08-15"


def test_extraction_job_is_durable_and_maps_cargos_before_selection() -> None:
    from app.document_processing import run_extraction_job

    db = next(_database())
    owner = _account(db)
    document = models.StudyDocument(
        user_id=owner.id,
        purpose="study_plan",
        file_name="edital.pdf",
        content_type="application/pdf",
        size_bytes=20,
        sha256="a" * 64,
        pdf_bytes=b"%PDF-1.7\nfake",
        status="extracting",
        progress=0,
    )
    db.add(document)
    db.flush()
    job = models.StudyDocumentJob(
        document_id=document.id,
        user_id=owner.id,
        kind="extract",
        status="queued",
        attempt_count=0,
        available_at=datetime.now(timezone.utc),
    )
    db.add(job)
    db.commit()

    def extractor(_pdf_bytes: bytes):
        return [
            {
                "page_number": 1,
                "text": "CARGO 1 - TECNICO ADMINISTRATIVO",
                "method": "native",
                "quality": 0.95,
            },
            {
                "page_number": 2,
                "text": "CARGO 2 - ANALISTA DE SISTEMAS\nDATA DA PROVA 10/10/2027",
                "method": "native",
                "quality": 0.95,
            },
        ]

    run_extraction_job(db, job.id, page_extractor=extractor)
    db.refresh(document)
    db.refresh(job)

    assert job.status == "completed"
    assert document.status == "awaiting_selection"
    assert document.progress == 55
    assert document.page_count == 2
    assert [item["title"] for item in document.cargos] == [
        "TECNICO ADMINISTRATIVO",
        "ANALISTA DE SISTEMAS",
    ]
    assert document.exam_date == "2027-10-10"
    assert (
        db.query(models.StudyDocumentPage)
        .filter(models.StudyDocumentPage.document_id == document.id)
        .count()
        == 2
    )


def test_library_extraction_completes_without_ai_or_cargo_selection() -> None:
    from app.document_processing import run_extraction_job

    db = next(_database())
    owner = _account(db)
    document = models.StudyDocument(
        user_id=owner.id,
        purpose="library",
        file_name="apostila.pdf",
        content_type="application/pdf",
        size_bytes=20,
        sha256="b" * 64,
        pdf_bytes=b"%PDF-1.7\nfake",
        status="extracting",
        progress=0,
    )
    db.add(document)
    db.flush()
    job = models.StudyDocumentJob(
        document_id=document.id,
        user_id=owner.id,
        kind="extract",
        status="queued",
        attempt_count=0,
        available_at=datetime.now(timezone.utc),
    )
    db.add(job)
    db.commit()

    run_extraction_job(
        db,
        job.id,
        page_extractor=lambda _content: [
            {
                "page_number": 1,
                "text": "Material completo da biblioteca.",
                "method": "native",
                "quality": 1.0,
            }
        ],
    )
    db.refresh(document)

    assert document.status == "ready"
    assert document.progress == 100
    assert document.extracted_text == "Material completo da biblioteca."


def test_claim_next_job_uses_a_lease_and_does_not_claim_twice() -> None:
    from app.document_processing import claim_next_job

    db = next(_database())
    owner = _account(db)
    document = models.StudyDocument(
        user_id=owner.id,
        purpose="library",
        file_name="apostila.pdf",
        content_type="application/pdf",
        size_bytes=10,
        sha256="c" * 64,
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
        status="queued",
        attempt_count=0,
        available_at=datetime.now(timezone.utc),
    )
    db.add(job)
    db.commit()

    first = claim_next_job(db, worker_id="worker-a")
    second = claim_next_job(db, worker_id="worker-b")

    assert first is not None
    assert first.locked_by == "worker-a"
    assert first.status == "running"
    assert second is None


def test_analysis_job_processes_late_pages_in_segments_and_consolidates_evidence() -> None:
    from app.document_processing import run_analysis_job

    db = next(_database())
    owner = _account(db)
    document = models.StudyDocument(
        user_id=owner.id,
        purpose="study_plan",
        file_name="edital.pdf",
        content_type="application/pdf",
        size_bytes=20,
        sha256="d" * 64,
        pdf_bytes=b"%PDF-1.7\nfake",
        status="analyzing",
        progress=60,
        cargos=[{"id": "cargo-2", "title": "Analista de Sistemas"}],
        selected_cargo_id="cargo-2",
        selected_cargo_title="Analista de Sistemas",
        exam_date="2027-10-10",
    )
    db.add(document)
    db.flush()
    for page_number, text in (
        (1, "Informacoes gerais " * 1000),
        (
            80,
            (
                "ANALISTA DE SISTEMAS\nCONHECIMENTOS ESPECIFICOS\n"
                "Banco de Dados: SQL e normalizacao."
            ),
        ),
        (
            81,
            (
                "ANALISTA DE SISTEMAS\n"
                "Banco de Dados: transacoes.\n"
                "Seguranca da Informacao: criptografia."
            ),
        ),
    ):
        db.add(
            models.StudyDocumentPage(
                document_id=document.id,
                page_number=page_number,
                text=text,
                extraction_method="native",
                quality=1,
                text_sha256=str(page_number) * 64,
            )
        )
    job = models.StudyDocumentJob(
        document_id=document.id,
        user_id=owner.id,
        kind="analyze",
        status="queued",
        attempt_count=0,
        payload={"cargo_id": "cargo-2", "cargo_title": "Analista de Sistemas"},
        available_at=datetime.now(timezone.utc),
    )
    db.add(job)
    db.commit()
    seen_windows: list[tuple[str, tuple[int, ...]]] = []

    def analyzer(text: str, page_numbers: tuple[int, ...], _index: int, _total: int):
        seen_windows.append((text, page_numbers))
        return {
            "disciplinas": [
                {
                    "nome": "Banco de Dados",
                    "topicos": ["SQL", "Normalizacao", "Transacoes"],
                    "evidencias": [
                        {"pagina": page, "trecho": "Banco de Dados"}
                        for page in page_numbers
                        if page in (80, 81)
                    ],
                },
                {
                    "nome": "Seguranca da Informacao",
                    "topicos": ["Criptografia"],
                    "evidencias": [
                        {"pagina": 81, "trecho": "Seguranca da Informacao"}
                    ],
                },
            ]
        }

    run_analysis_job(db, job.id, analyzer=analyzer, max_window_chars=1800)
    db.refresh(document)
    db.refresh(job)

    assert job.status == "completed"
    assert document.status == "ready"
    assert document.progress == 100
    assert any(80 in pages for _text, pages in seen_windows)
    assert any(81 in pages for _text, pages in seen_windows)
    assert [item["nome"] for item in document.analysis_result["disciplinas"]] == [
        "Banco de Dados",
        "Seguranca da Informacao",
    ]
    banco = document.analysis_result["disciplinas"][0]
    assert banco["topicos"] == ["SQL", "Normalizacao", "Transacoes"]
    assert {item["pagina"] for item in banco["evidencias"]} == {80, 81}
    assert document.analysis_result["data_prova"] == "2027-10-10"


def test_analysis_without_grounded_subjects_requires_review_instead_of_losing_job() -> None:
    from app.document_processing import run_analysis_job

    db = next(_database())
    owner = _account(db)
    document = models.StudyDocument(
        user_id=owner.id,
        purpose="study_plan",
        file_name="edital.pdf",
        content_type="application/pdf",
        size_bytes=20,
        sha256="e" * 64,
        pdf_bytes=b"%PDF-1.7\nfake",
        status="analyzing",
        progress=60,
        cargos=[{"id": "cargo", "title": "Analista"}],
        selected_cargo_id="cargo",
        selected_cargo_title="Analista",
    )
    db.add(document)
    db.flush()
    db.add(
        models.StudyDocumentPage(
            document_id=document.id,
            page_number=1,
            text="ANALISTA - conteudo pouco claro",
            extraction_method="native",
            quality=0.8,
            text_sha256="f" * 64,
        )
    )
    job = models.StudyDocumentJob(
        document_id=document.id,
        user_id=owner.id,
        kind="analyze",
        status="queued",
        attempt_count=0,
        payload={"cargo_id": "cargo", "cargo_title": "Analista"},
        available_at=datetime.now(timezone.utc),
    )
    db.add(job)
    db.commit()

    run_analysis_job(
        db,
        job.id,
        analyzer=lambda *_args: {"disciplinas": []},
    )
    db.refresh(document)
    db.refresh(job)

    assert job.status == "completed"
    assert document.status == "needs_review"
    assert document.error_code == "subjects_not_found"
    assert "tentar novamente" in document.error_message.lower()


def test_analysis_splits_only_oversized_segment_and_persists_checkpoints() -> None:
    from app.document_processing import DocumentProcessingError, run_analysis_job

    db = next(_database())
    owner = _account(db)
    document = models.StudyDocument(
        user_id=owner.id,
        purpose="study_plan",
        file_name="edital.pdf",
        content_type="application/pdf",
        size_bytes=20,
        sha256="1" * 64,
        status="analyzing",
        progress=60,
        cargos=[{"id": "cargo", "title": "Analista"}],
        selected_cargo_id="cargo",
        selected_cargo_title="Analista",
    )
    db.add(document)
    db.flush()
    db.add(
        models.StudyDocumentPage(
            document_id=document.id,
            page_number=9,
            text=(
                "ANALISTA\nCONTEUDO PROGRAMATICO\n"
                + ("Banco de Dados: SQL e normalizacao.\n" * 180)
            ),
            extraction_method="native",
            quality=1,
            text_sha256="2" * 64,
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
    attempted_sizes: list[int] = []

    def analyzer(text, pages, _index, _total):
        attempted_sizes.append(len(text))
        if len(text) > 4_000:
            raise DocumentProcessingError(
                "payload_too_large",
                "Segmento excedeu o limite do provedor.",
            )
        return {
            "disciplinas": [
                {
                    "nome": "Banco de Dados",
                    "topicos": ["SQL"],
                    "evidencias": [{"pagina": pages[0], "trecho": "SQL"}],
                }
            ]
        }

    run_analysis_job(db, job.id, analyzer=analyzer)
    db.refresh(job)
    db.refresh(document)

    assert attempted_sizes[0] > 4_000
    assert any(size <= 4_000 for size in attempted_sizes[1:])
    assert job.status == "completed"
    assert document.status == "ready"
    assert len(job.result["checkpoints"]) >= 2
    assert all(len(key) == 64 for key in job.result["checkpoints"])


def test_analysis_splits_segment_when_provider_returns_invalid_schema() -> None:
    from app.document_processing import DocumentProcessingError, run_analysis_job

    db = next(_database())
    owner = _account(db)
    document = models.StudyDocument(
        user_id=owner.id,
        purpose="study_plan",
        file_name="edital.pdf",
        content_type="application/pdf",
        size_bytes=20,
        sha256="7" * 64,
        status="analyzing",
        progress=60,
        cargos=[{"id": "cargo", "title": "Analista"}],
        selected_cargo_id="cargo",
        selected_cargo_title="Analista",
    )
    db.add(document)
    db.flush()
    db.add(
        models.StudyDocumentPage(
            document_id=document.id,
            page_number=29,
            text=(
                "ANALISTA\nCONTEUDO PROGRAMATICO\n"
                + ("Engenharia de Software: requisitos e testes.\n" * 180)
            ),
            extraction_method="native",
            quality=1,
            text_sha256="8" * 64,
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
    attempted_sizes: list[int] = []

    def analyzer(text, pages, _index, _total):
        attempted_sizes.append(len(text))
        if len(text) > 4_000:
            raise DocumentProcessingError(
                "analysis_response_invalid",
                "O provedor retornou uma resposta incompleta.",
            )
        return {
            "disciplinas": [
                {
                    "nome": "Engenharia de Software",
                    "topicos": ["Requisitos", "Testes"],
                    "evidencias": [
                        {"pagina": pages[0], "trecho": "requisitos e testes"}
                    ],
                }
            ]
        }

    run_analysis_job(db, job.id, analyzer=analyzer)
    db.refresh(document)

    assert attempted_sizes[0] > 4_000
    assert any(size <= 4_000 for size in attempted_sizes[1:])
    assert document.status == "ready"


def test_analysis_retry_resumes_from_persisted_checkpoint() -> None:
    from app.document_processing import DocumentProcessingError, run_analysis_job

    db = next(_database())
    owner = _account(db)
    document = models.StudyDocument(
        user_id=owner.id,
        purpose="study_plan",
        file_name="edital.pdf",
        content_type="application/pdf",
        size_bytes=20,
        sha256="3" * 64,
        status="analyzing",
        progress=60,
        cargos=[{"id": "cargo", "title": "Analista"}],
        selected_cargo_id="cargo",
        selected_cargo_title="Analista",
    )
    db.add(document)
    db.flush()
    db.add(
        models.StudyDocumentPage(
            document_id=document.id,
            page_number=1,
            text=(
                "ANALISTA\nCONTEUDO PROGRAMATICO\n"
                + ("Banco de Dados: SQL.\n" * 150)
            ),
            extraction_method="native",
            quality=1,
            text_sha256="4" * 64,
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
    first_attempt_texts: list[str] = []

    def interrupted(text, pages, _index, _total):
        first_attempt_texts.append(text)
        if len(first_attempt_texts) == 2:
            raise DocumentProcessingError(
                "provider_unavailable",
                "Provedor temporariamente indisponivel.",
                retryable=True,
            )
        return {
            "disciplinas": [
                {
                    "nome": "Banco de Dados",
                    "topicos": ["SQL"],
                    "evidencias": [{"pagina": pages[0], "trecho": "SQL"}],
                }
            ]
        }

    run_analysis_job(db, job.id, analyzer=interrupted, max_window_chars=1_800)
    db.refresh(job)
    assert job.status == "retrying"
    assert len(job.result["checkpoints"]) == 1
    completed_text = first_attempt_texts[0]

    resumed_texts: list[str] = []

    def resumed(text, pages, _index, _total):
        resumed_texts.append(text)
        return {
            "disciplinas": [
                {
                    "nome": "Banco de Dados",
                    "topicos": ["SQL"],
                    "evidencias": [{"pagina": pages[0], "trecho": "SQL"}],
                }
            ]
        }

    job.attempt_count = 2
    run_analysis_job(db, job.id, analyzer=resumed, max_window_chars=1_800)
    db.refresh(job)

    assert job.status == "completed"
    assert completed_text not in resumed_texts
    assert len(job.result["checkpoints"]) >= 2


def test_analysis_retry_recomputes_invalid_persisted_checkpoint() -> None:
    from app.document_processing import (
        _analysis_window_hash,
        build_analysis_windows,
        run_analysis_job,
    )

    db = next(_database())
    owner = _account(db)
    page_text = (
        "ANALISTA\nCONTEUDO PROGRAMATICO\n"
        "Engenharia de Software: requisitos e testes."
    )
    document = models.StudyDocument(
        user_id=owner.id,
        purpose="study_plan",
        file_name="edital.pdf",
        content_type="application/pdf",
        size_bytes=20,
        sha256="9" * 64,
        status="analyzing",
        progress=60,
        cargos=[{"id": "cargo", "title": "Analista"}],
        selected_cargo_id="cargo",
        selected_cargo_title="Analista",
    )
    db.add(document)
    db.flush()
    db.add(
        models.StudyDocumentPage(
            document_id=document.id,
            page_number=29,
            text=page_text,
            extraction_method="native",
            quality=1,
            text_sha256="a" * 64,
        )
    )
    window = build_analysis_windows(
        [{"page_number": 29, "text": page_text}],
        cargo_title="Analista",
    )[0]
    checkpoint_key = _analysis_window_hash(
        cargo_title="Analista",
        window=window,
    )
    job = models.StudyDocumentJob(
        document_id=document.id,
        user_id=owner.id,
        kind="analyze",
        status="running",
        attempt_count=2,
        payload={"cargo_id": "cargo", "cargo_title": "Analista"},
        result={
            "checkpoints": {
                checkpoint_key: {
                    "state": "completed",
                    "partial": {},
                    "page_numbers": [29],
                }
            }
        },
        available_at=datetime.now(timezone.utc),
    )
    db.add(job)
    db.commit()
    calls = 0

    def analyzer(_text, pages, _index, _total):
        nonlocal calls
        calls += 1
        return {
            "disciplinas": [
                {
                    "nome": "Engenharia de Software",
                    "topicos": ["Requisitos", "Testes"],
                    "evidencias": [
                        {"pagina": pages[0], "trecho": "requisitos e testes"}
                    ],
                }
            ]
        }

    run_analysis_job(db, job.id, analyzer=analyzer)
    db.refresh(document)

    assert calls == 1
    assert document.status == "ready"


def test_manual_cargo_with_early_vacancy_and_distant_syllabus_becomes_ready():
    from app.document_processing import run_analysis_job

    db = next(_database())
    owner = _account(db)
    document = models.StudyDocument(
        user_id=owner.id, purpose="study_plan", file_name="edital.pdf",
        content_type="application/pdf", size_bytes=20, sha256="8" * 64,
        status="analyzing", progress=60, cargos=[],
        selected_cargo_id="manual", selected_cargo_title="Analista de Sistemas",
    )
    db.add(document)
    db.flush()
    for number in range(1, 18):
        text = "Informacoes administrativas."
        if number == 1:
            text = "Quadro de vagas: Analista de Sistemas"
        elif number == 9:
            text = "CONTEUDO PROGRAMATICO"
        elif number == 16:
            text = "Banco de dados: normalizacao e transacoes."
        db.add(models.StudyDocumentPage(document_id=document.id,
            page_number=number, text=text, extraction_method="native",
            quality=1, text_sha256="a" * 64))
    job = models.StudyDocumentJob(document_id=document.id, user_id=owner.id,
        kind="analyze", status="queued", attempt_count=0,
        payload={"cargo_id": "manual", "cargo_title": "Analista de Sistemas"},
        available_at=datetime.now(timezone.utc))
    db.add(job)
    db.commit()

    def analyzer(text, pages, _index, _total):
        if "normalizacao" not in text:
            return {"disciplinas": []}
        return {"disciplinas": [{"nome": "Banco de dados",
            "topicos": ["Normalizacao", "Transacoes"],
            "evidencias": [{"pagina": 16, "trecho": "normalizacao e transacoes"}]}]}

    run_analysis_job(db, job.id, analyzer=analyzer)
    db.refresh(document)
    db.refresh(job)
    assert job.status == "completed"
    assert document.status == "ready"
    assert document.analysis_result["disciplinas"][0]["nome"] == "Banco de dados"
    assert 16 in document.analysis_result["paginas_analisadas"]
