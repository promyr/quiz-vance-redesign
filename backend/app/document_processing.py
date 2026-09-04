from __future__ import annotations

import hashlib
import json
import logging
import os
import re
import shutil
import subprocess
import tempfile
import unicodedata
import uuid
from collections.abc import Callable, Iterable
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from sqlalchemy import or_
from sqlalchemy.orm import Session

from . import models
from .document_analysis import (
    AnalysisWindow,
    split_analysis_window,
)
from .document_analysis import (
    analysis_window_hash as _analysis_window_hash,
)
from .document_analysis import (
    consolidate_analysis as _consolidate_analysis,
)
from .document_storage import DocumentStorage, DocumentStorageError

logger = logging.getLogger(__name__)

MAX_PDF_BYTES = max(
    1_048_576, int(os.getenv("STUDY_DOCUMENT_MAX_BYTES", str(100 * 1024 * 1024)))
)
MAX_PDF_PAGES = max(1, int(os.getenv("STUDY_DOCUMENT_MAX_PAGES", "2000")))
MIN_NATIVE_PAGE_CHARS = max(
    5, int(os.getenv("STUDY_DOCUMENT_MIN_NATIVE_PAGE_CHARS", "40"))
)
ANALYSIS_MAX_WINDOW_CHARS = max(
    2_000, int(os.getenv("STUDY_DOCUMENT_ANALYSIS_WINDOW_CHARS", "8000"))
)
ANALYSIS_MIN_SPLIT_CHARS = max(
    500, int(os.getenv("STUDY_DOCUMENT_ANALYSIS_MIN_SPLIT_CHARS", "1000"))
)
ANALYSIS_CHECKPOINT_VERSION = 1


class DocumentValidationError(ValueError):
    pass


class DocumentProcessingError(RuntimeError):
    def __init__(
        self,
        code: str,
        message: str,
        *,
        retryable: bool = False,
        retry_after_seconds: int | None = None,
    ):
        super().__init__(message)
        self.code = code
        self.retryable = retryable
        self.retry_after_seconds = retry_after_seconds


@dataclass(frozen=True)
class PdfUploadMetadata:
    file_name: str
    size_bytes: int
    sha256: str


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _plain(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", str(value or ""))
    ascii_text = "".join(ch for ch in normalized if not unicodedata.combining(ch))
    return re.sub(r"\s+", " ", ascii_text).strip().lower()


def validate_pdf_upload(
    *,
    file_name: str,
    content_type: str | None,
    content: bytes,
    max_bytes: int = MAX_PDF_BYTES,
) -> PdfUploadMetadata:
    safe_name = Path(str(file_name or "").replace("\\", "/")).name.strip()
    normalized_type = str(content_type or "").split(";", 1)[0].strip().lower()
    if not safe_name.lower().endswith(".pdf") or normalized_type not in {
        "",
        "application/pdf",
        "application/octet-stream",
    }:
        raise DocumentValidationError("somente pdf e aceito.")
    if not content:
        raise DocumentValidationError("PDF vazio.")
    if len(content) > max_bytes:
        raise DocumentValidationError(
            f"O PDF excede o limite operacional de {max_bytes // (1024 * 1024)} MiB."
        )
    if content.find(b"%PDF-", 0, min(len(content), 1024)) < 0:
        raise DocumentValidationError("pdf invalido: assinatura nao encontrada.")
    return PdfUploadMetadata(
        file_name=safe_name[:255] or "documento.pdf",
        size_bytes=len(content),
        sha256=hashlib.sha256(content).hexdigest(),
    )


def _normalized_page(page: dict[str, Any]) -> dict[str, Any]:
    text = re.sub(r"[ \t]{3,}", " ", str(page.get("text") or ""))
    text = re.sub(r"\n{4,}", "\n\n", text).strip()
    return {
        "page_number": max(1, int(page.get("page_number") or 1)),
        "text": text,
        "method": str(page.get("method") or "native")[:20],
        "quality": max(0.0, min(1.0, float(page.get("quality") or 0.0))),
    }


def _ocr_page(pdf_path: Path, page_number: int, temp_dir: Path) -> str:
    pdftoppm = shutil.which("pdftoppm")
    tesseract = shutil.which("tesseract")
    if not pdftoppm or not tesseract:
        return ""
    prefix = temp_dir / f"ocr-{page_number}"
    try:
        subprocess.run(
            [
                pdftoppm,
                "-f",
                str(page_number),
                "-l",
                str(page_number),
                "-r",
                "200",
                "-png",
                "-singlefile",
                str(pdf_path),
                str(prefix),
            ],
            check=True,
            capture_output=True,
            timeout=45,
        )
        image_path = prefix.with_suffix(".png")
        result = subprocess.run(
            [tesseract, str(image_path), "stdout", "-l", "por+eng"],
            check=True,
            capture_output=True,
            timeout=60,
        )
        return result.stdout.decode("utf-8", errors="replace").strip()
    except (OSError, subprocess.SubprocessError):
        logger.warning(
            "study_document_ocr_failed",
            extra={"page_number": page_number},
        )
        return ""


def extract_pdf_pages(pdf_bytes: bytes) -> list[dict[str, Any]]:
    try:
        from pypdf import PdfReader
    except ImportError as exc:
        raise DocumentProcessingError(
            "pdf_engine_missing",
            "Motor de leitura de PDF indisponivel.",
        ) from exc

    with tempfile.TemporaryDirectory(prefix="quiz-vance-pdf-") as temp_name:
        temp_dir = Path(temp_name)
        pdf_path = temp_dir / "document.pdf"
        pdf_path.write_bytes(pdf_bytes)
        try:
            reader = PdfReader(str(pdf_path), strict=False)
        except Exception as exc:
            raise DocumentProcessingError(
                "invalid_pdf",
                "Nao foi possivel abrir o PDF.",
            ) from exc
        if reader.is_encrypted:
            raise DocumentProcessingError(
                "encrypted_pdf",
                "O PDF possui senha. Remova a protecao e tente novamente.",
            )
        if len(reader.pages) > MAX_PDF_PAGES:
            raise DocumentProcessingError(
                "too_many_pages",
                f"O PDF excede o limite operacional de {MAX_PDF_PAGES} paginas.",
            )

        extracted: list[dict[str, Any]] = []
        for index, page in enumerate(reader.pages, start=1):
            try:
                native_text = str(page.extract_text() or "").strip()
            except Exception:  # noqa: BLE001 - pypdf expõe falhas heterogêneas
                native_text = ""
            method = "native"
            text = native_text
            if len(_plain(native_text)) < MIN_NATIVE_PAGE_CHARS:
                ocr_text = _ocr_page(pdf_path, index, temp_dir)
                if len(_plain(ocr_text)) > len(_plain(native_text)):
                    text = ocr_text
                    method = "ocr"
            quality = min(1.0, len(_plain(text)) / 500.0)
            extracted.append(
                {
                    "page_number": index,
                    "text": text,
                    "method": method,
                    "quality": quality,
                }
            )

        total_extracted_chars = sum(len(_plain(p["text"])) for p in extracted)
        if total_extracted_chars < 30 and len(reader.pages) > 0:
            raise DocumentValidationError(
                "O arquivo PDF enviado parece ser uma imagem digitalizada sem camada de texto legível. "
                "Por favor, envie um documento com texto selecionável para gerar questões e materiais."
            )

        return extracted


_CARGO_PATTERNS = (
    re.compile(
        r"^\s*(?:cargo|emprego)\s*(?:n[ºo.]*)?\s*[\w.-]*\s*[-:]\s*(.{3,180})$",
        re.IGNORECASE,
    ),
    re.compile(
        r"^\s*(?:cargo|emprego)\s+(?:de\s+)?(.{3,180})$",
        re.IGNORECASE,
    ),
    re.compile(
        r"^\s*(?:perfil(?:\s+profissional)?|especialidade|funcao|função)"
        r"\s*[-:]\s*(.{3,180})$",
        re.IGNORECASE,
    ),
)
_DATE_PATTERN = re.compile(r"\b([0-3]?\d)[/-]([01]?\d)[/-]((?:20)\d{2})\b")


def discover_notice_metadata(
    pages: Iterable[dict[str, Any]],
) -> tuple[list[dict[str, Any]], str | None]:
    cargos: list[dict[str, Any]] = []
    seen: set[str] = set()
    exam_date: str | None = None
    for page in pages:
        text = str(page.get("text") or "")
        lines = [line.strip(" \t-:;") for line in text.splitlines() if line.strip()]
        for line in lines:
            for pattern in _CARGO_PATTERNS:
                match = pattern.match(line)
                if not match:
                    continue
                title = re.sub(r"\s+", " ", match.group(1)).strip(" .:;-")
                key = _plain(title)
                if key and key not in seen:
                    seen.add(key)
                    cargos.append(
                        {
                            "id": hashlib.sha256(key.encode("utf-8")).hexdigest()[:16],
                            "title": title,
                            "page_number": int(page.get("page_number") or 1),
                        }
                    )
                break
        if exam_date is None and any(
            marker in _plain(text)
            for marker in ("data da prova", "aplicacao da prova", "realizacao da prova")
        ):
            match = _DATE_PATTERN.search(text)
            if match:
                day, month, year = (int(part) for part in match.groups())
                try:
                    exam_date = (
                        datetime(year, month, day, tzinfo=timezone.utc)
                        .date()
                        .isoformat()
                    )
                except ValueError:
                    pass
    return cargos[:250], exam_date


def build_analysis_windows(
    pages: Iterable[dict[str, Any]],
    *,
    cargo_title: str,
    max_chars: int = ANALYSIS_MAX_WINDOW_CHARS,
) -> list[AnalysisWindow]:
    normalized_pages = [_normalized_page(page) for page in pages]
    cargo_key = _plain(cargo_title)
    cargo_markers = [cargo_key] if cargo_key else []
    profile_match = re.search(r"\bperfil\s*:?\s*(\d+)\b", cargo_key)
    if profile_match:
        cargo_markers.append(f"perfil {profile_match.group(1)}")

    generic_markers = (
        "conteudo programatico",
        "conhecimentos especificos",
        "conhecimentos gerais",
        "programa da prova",
    )
    cargo_indexes: set[int] = set()
    generic_indexes: set[int] = set()
    for index, page in enumerate(normalized_pages):
        page_key = _plain(page["text"])
        if any(marker and marker in page_key for marker in cargo_markers):
            cargo_indexes.update(
                item
                for item in range(max(0, index - 1), min(len(normalized_pages), index + 3))
            )
        if any(marker in page_key for marker in generic_markers):
            generic_indexes.update(
                item
                for item in range(max(0, index - 1), min(len(normalized_pages), index + 3))
            )

    candidate_indexes = cargo_indexes or generic_indexes
    if not candidate_indexes:
        candidate_indexes.update(range(len(normalized_pages)))

    windows: list[AnalysisWindow] = []
    current_parts: list[str] = []
    current_pages: list[int] = []
    current_size = 0

    def flush() -> None:
        nonlocal current_parts, current_pages, current_size
        if current_parts:
            windows.append(
                AnalysisWindow(
                    text="\n\n".join(current_parts)[:max_chars],
                    page_numbers=tuple(dict.fromkeys(current_pages)),
                )
            )
        current_parts = []
        current_pages = []
        current_size = 0

    for index in sorted(candidate_indexes):
        page = normalized_pages[index]
        page_text = f"[PAGINA {page['page_number']}]\n{page['text']}".strip()
        if not page_text:
            continue
        start = 0
        while start < len(page_text):
            remaining = max_chars - current_size
            if remaining <= 100:
                flush()
                remaining = max_chars
            piece = page_text[start : start + remaining]
            current_parts.append(piece)
            current_pages.append(page["page_number"])
            current_size += len(piece) + 2
            start += len(piece)
            if current_size >= max_chars:
                flush()
    flush()
    return windows


def claim_next_job(
    db: Session,
    *,
    worker_id: str | None = None,
    lease_seconds: int = 180,
) -> models.StudyDocumentJob | None:
    now = _now()
    query = (
        db.query(models.StudyDocumentJob)
        .filter(
            models.StudyDocumentJob.attempt_count
            < models.StudyDocumentJob.max_attempts,
            models.StudyDocumentJob.available_at <= now,
            or_(
                models.StudyDocumentJob.status.in_(("queued", "retrying")),
                (
                    (models.StudyDocumentJob.status == "running")
                    & (models.StudyDocumentJob.locked_until <= now)
                ),
            ),
        )
        .order_by(
            models.StudyDocumentJob.available_at.asc(),
            models.StudyDocumentJob.id.asc(),
        )
    )
    query = query.with_for_update(skip_locked=True)
    job = query.first()
    if job is None:
        return None
    job.status = "running"
    job.locked_by = (worker_id or f"worker-{uuid.uuid4().hex[:12]}")[:120]
    job.locked_until = now + timedelta(seconds=max(30, lease_seconds))
    job.attempt_count = int(job.attempt_count or 0) + 1
    job.updated_at = now
    db.commit()
    db.refresh(job)
    return job


def _finish_job(
    db: Session,
    job: models.StudyDocumentJob,
    *,
    result: dict[str, Any] | None = None,
) -> None:
    job.status = "completed"
    job.progress = 100
    job.result = result or {}
    job.error_code = None
    job.error_message = None
    job.locked_by = None
    job.locked_until = None
    job.updated_at = _now()
    db.commit()


def _fail_job(
    db: Session,
    job: models.StudyDocumentJob,
    document: models.StudyDocument,
    exc: Exception,
) -> None:
    retryable = isinstance(exc, DocumentProcessingError) and exc.retryable
    can_retry = retryable and int(job.attempt_count or 0) < int(job.max_attempts or 3)
    code = (
        exc.code
        if isinstance(exc, DocumentProcessingError)
        else "document_processing_failed"
    )
    message = (
        str(exc)[:500] or "Falha ao processar o PDF."
        if isinstance(exc, DocumentProcessingError)
        else "Nao foi possivel processar o documento."
    )
    job.status = "retrying" if can_retry else "failed"
    retry_delay = min(
        15 * 60,
        max(
            30 * (2 ** max(0, int(job.attempt_count or 1) - 1)),
            int(getattr(exc, "retry_after_seconds", 0) or 0),
        ),
    )
    job.available_at = _now() + timedelta(seconds=retry_delay)
    job.error_code = code
    job.error_message = message
    job.locked_by = None
    job.locked_until = None
    job.updated_at = _now()
    if can_retry:
        document.status = "analyzing" if job.kind == "analyze" else "extracting"
    else:
        document.status = "failed"
    document.error_code = code
    document.error_message = message
    document.updated_at = _now()
    db.commit()


def run_extraction_job(
    db: Session,
    job_id: int,
    *,
    page_extractor: Callable[[bytes], list[dict[str, Any]]] = extract_pdf_pages,
) -> None:
    job = (
        db.query(models.StudyDocumentJob)
        .filter(models.StudyDocumentJob.id == int(job_id))
        .first()
    )
    if job is None:
        raise LookupError("Job nao encontrado.")
    document = (
        db.query(models.StudyDocument)
        .filter(models.StudyDocument.id == int(job.document_id))
        .first()
    )
    if document is None:
        raise LookupError("Documento nao encontrado.")
    try:
        job.status = "running"
        job.progress = 5
        document.status = "extracting"
        document.progress = 5
        document.error_code = None
        document.error_message = None
        db.commit()

        pdf_content = document.pdf_bytes
        if document.storage_key:
            try:
                pdf_content = DocumentStorage.from_environment().read(
                    document.storage_key
                )
            except DocumentStorageError as exc:
                raise DocumentProcessingError(
                    "document_storage_unavailable",
                    str(exc),
                    retryable=True,
                ) from exc
        if not pdf_content:
            raise DocumentProcessingError(
                "document_storage_missing",
                "O PDF privado nao esta disponivel para processamento.",
                retryable=True,
            )
        pages = [_normalized_page(page) for page in page_extractor(pdf_content)]
        if not pages:
            raise DocumentProcessingError(
                "empty_pdf",
                "O PDF nao possui paginas legiveis.",
            )
        if len(pages) > MAX_PDF_PAGES:
            raise DocumentProcessingError(
                "too_many_pages",
                f"O PDF excede o limite de {MAX_PDF_PAGES} paginas.",
            )
        if not any(page["text"] for page in pages):
            raise DocumentProcessingError(
                "ocr_no_text",
                "Nao foi possivel extrair texto do PDF, inclusive por OCR.",
            )

        db.query(models.StudyDocumentPage).filter(
            models.StudyDocumentPage.document_id == document.id
        ).delete(synchronize_session=False)
        for page in pages:
            db.add(
                models.StudyDocumentPage(
                    document_id=document.id,
                    page_number=page["page_number"],
                    text=page["text"],
                    extraction_method=page["method"],
                    quality=page["quality"],
                    text_sha256=hashlib.sha256(
                        page["text"].encode("utf-8")
                    ).hexdigest(),
                )
            )
        document.page_count = len(pages)
        document.progress = 45
        job.progress = 75
        db.flush()

        joined_text = "\n\n".join(page["text"] for page in pages if page["text"])
        storage_key = document.storage_key
        document.storage_key = None
        if document.purpose == "library":
            document.extracted_text = joined_text
            document.status = "ready"
            document.progress = 100
            document.updated_at = _now()
            _finish_job(
                db,
                job,
                result={"page_count": len(pages), "purpose": "library"},
            )
            try:
                DocumentStorage.from_environment().delete(storage_key)
            except Exception:
                logger.exception(
                    "study_document_source_cleanup_failed",
                    extra={"document_id": document.id},
                )
            return

        cargos, exam_date = discover_notice_metadata(pages)
        document.cargos = cargos
        document.exam_date = exam_date
        document.status = "awaiting_selection" if cargos else "needs_review"
        document.progress = 55
        document.updated_at = _now()
        _finish_job(
            db,
            job,
            result={
                "page_count": len(pages),
                "cargo_count": len(cargos),
                "exam_date": exam_date,
            },
        )
        try:
            DocumentStorage.from_environment().delete(storage_key)
        except Exception:
            logger.exception(
                "study_document_source_cleanup_failed",
                extra={"document_id": document.id},
            )
    except Exception as exc:
        logger.exception(
            "study_document_extraction_failed",
            extra={"document_id": document.id, "job_id": job.id},
        )
        _fail_job(db, job, document, exc)


def _split_analysis_window(window: AnalysisWindow) -> tuple[AnalysisWindow, ...]:
    return split_analysis_window(
        window,
        minimum_chars=ANALYSIS_MIN_SPLIT_CHARS,
    )


def _checkpoint_map(job: models.StudyDocumentJob) -> dict[str, dict[str, Any]]:
    raw_result = job.result if isinstance(job.result, dict) else {}
    raw_checkpoints = raw_result.get("checkpoints")
    if not isinstance(raw_checkpoints, dict):
        return {}
    return {
        str(key): value
        for key, value in raw_checkpoints.items()
        if isinstance(key, str) and isinstance(value, dict)
    }


def _persist_analysis_checkpoints(
    db: Session,
    job: models.StudyDocumentJob,
    *,
    cargo_title: str,
    checkpoints: dict[str, dict[str, Any]],
) -> None:
    previous = job.result if isinstance(job.result, dict) else {}
    job.result = {
        **previous,
        "checkpoint_version": ANALYSIS_CHECKPOINT_VERSION,
        "cargo_title_hash": hashlib.sha256(
            _plain(cargo_title).encode("utf-8")
        ).hexdigest(),
        "checkpoints": dict(checkpoints),
    }
    job.locked_until = _now() + timedelta(seconds=180)
    job.updated_at = _now()
    db.commit()


def _update_analysis_progress(
    job: models.StudyDocumentJob,
    document: models.StudyDocument,
    *,
    base_window_count: int,
    checkpoints: dict[str, dict[str, Any]],
) -> None:
    completed = sum(
        1
        for item in checkpoints.values()
        if isinstance(item.get("partial"), dict)
    )
    split_count = sum(
        1 for item in checkpoints.values() if item.get("state") == "split"
    )
    expected_leaves = max(1, base_window_count + split_count)
    ratio = min(1.0, completed / expected_leaves)
    job.progress = min(90, 5 + int(ratio * 85))
    document.progress = min(94, 62 + int(ratio * 32))


def run_analysis_job(
    db: Session,
    job_id: int,
    *,
    analyzer: Callable[
        [str, tuple[int, ...], int, int], dict[str, Any]
    ],
    max_window_chars: int = ANALYSIS_MAX_WINDOW_CHARS,
) -> None:
    job = (
        db.query(models.StudyDocumentJob)
        .filter(models.StudyDocumentJob.id == int(job_id))
        .first()
    )
    if job is None:
        raise LookupError("Job nao encontrado.")
    document = (
        db.query(models.StudyDocument)
        .filter(models.StudyDocument.id == int(job.document_id))
        .first()
    )
    if document is None:
        raise LookupError("Documento nao encontrado.")
    try:
        cargo_title = str(
            (job.payload or {}).get("cargo_title")
            or document.selected_cargo_title
            or ""
        ).strip()
        if not cargo_title:
            raise DocumentProcessingError(
                "cargo_not_selected",
                "Selecione um cargo antes de analisar o edital.",
            )
        rows = (
            db.query(models.StudyDocumentPage)
            .filter(models.StudyDocumentPage.document_id == document.id)
            .order_by(models.StudyDocumentPage.page_number.asc())
            .all()
        )
        if not rows:
            raise DocumentProcessingError(
                "pages_missing",
                "As paginas extraidas nao foram encontradas.",
            )
        pages = [
            {"page_number": row.page_number, "text": row.text}
            for row in rows
        ]
        windows = build_analysis_windows(
            pages,
            cargo_title=cargo_title,
            max_chars=max_window_chars,
        )
        if not windows:
            raise DocumentProcessingError(
                "analysis_context_empty",
                "Nao foi encontrado texto para analisar.",
            )

        job.status = "running"
        job.progress = 5
        document.status = "analyzing"
        document.progress = 62
        document.error_code = None
        document.error_message = None
        db.commit()

        partials: list[tuple[dict[str, Any], tuple[int, ...]]] = []
        checkpoints = _checkpoint_map(job)
        total = len(windows)

        def analyze_resiliently(
            window: AnalysisWindow,
            *,
            index: int,
        ) -> list[tuple[dict[str, Any], tuple[int, ...]]]:
            checkpoint_key = _analysis_window_hash(
                cargo_title=cargo_title,
                window=window,
            )
            existing = checkpoints.get(checkpoint_key)
            if isinstance(existing, dict):
                existing_partial = existing.get("partial")
                if isinstance(existing_partial, dict) and isinstance(
                    existing_partial.get("disciplinas"), list
                ):
                    stored_pages = existing.get("page_numbers")
                    page_numbers = (
                        tuple(int(page) for page in stored_pages)
                        if isinstance(stored_pages, list)
                        else window.page_numbers
                    )
                    return [(existing_partial, page_numbers)]
                if existing.get("state") == "split":
                    children = _split_analysis_window(window)
                    if children:
                        recovered: list[
                            tuple[dict[str, Any], tuple[int, ...]]
                        ] = []
                        for child in children:
                            recovered.extend(
                                analyze_resiliently(child, index=index)
                            )
                        return recovered

            try:
                partial = analyzer(
                    window.text,
                    window.page_numbers,
                    index,
                    total,
                )
            except DocumentProcessingError as exc:
                if exc.code not in {
                    "payload_too_large",
                    "analysis_response_invalid",
                }:
                    raise
                children = _split_analysis_window(window)
                if not children:
                    raise DocumentProcessingError(
                        "payload_too_large",
                        "Mesmo o menor segmento excedeu o limite do provedor.",
                    ) from exc
                checkpoints[checkpoint_key] = {
                    "state": "split",
                    "page_numbers": list(window.page_numbers),
                    "text_chars": len(window.text),
                }
                _update_analysis_progress(
                    job,
                    document,
                    base_window_count=total,
                    checkpoints=checkpoints,
                )
                _persist_analysis_checkpoints(
                    db,
                    job,
                    cargo_title=cargo_title,
                    checkpoints=checkpoints,
                )
                logger.info(
                    "study_document_analysis_segment_split",
                    extra={
                        "document_id": document.id,
                        "job_id": job.id,
                        "segment_hash": checkpoint_key[:12],
                        "text_chars": len(window.text),
                        "child_count": len(children),
                        "attempt": int(job.attempt_count or 0),
                    },
                )
                split_partials: list[
                    tuple[dict[str, Any], tuple[int, ...]]
                ] = []
                for child in children:
                    split_partials.extend(
                        analyze_resiliently(child, index=index)
                    )
                return split_partials

            safe_partial = partial if isinstance(partial, dict) else {}
            checkpoints[checkpoint_key] = {
                "state": "completed",
                "partial": safe_partial,
                "page_numbers": list(window.page_numbers),
                "text_chars": len(window.text),
            }
            _update_analysis_progress(
                job,
                document,
                base_window_count=total,
                checkpoints=checkpoints,
            )
            _persist_analysis_checkpoints(
                db,
                job,
                cargo_title=cargo_title,
                checkpoints=checkpoints,
            )
            return [(safe_partial, window.page_numbers)]

        for index, window in enumerate(windows, start=1):
            try:
                partials.extend(analyze_resiliently(window, index=index))
            except DocumentProcessingError as exc:
                logger.warning(
                    "study_document_analysis_segment_failed",
                    extra={
                        "document_id": document.id,
                        "job_id": job.id,
                        "segment_index": index,
                        "segment_total": total,
                        "segment_hash": _analysis_window_hash(
                            cargo_title=cargo_title,
                            window=window,
                        )[:12],
                        "error_code": exc.code,
                        "attempt": int(job.attempt_count or 0),
                    },
                )
                raise
            job.locked_until = _now() + timedelta(seconds=180)
            job.updated_at = _now()
            document.updated_at = _now()
            db.commit()

        disciplines = _consolidate_analysis(partials)
        document.analysis_result = {
            "cargo_id": document.selected_cargo_id,
            "cargo": cargo_title,
            "data_prova": document.exam_date,
            "disciplinas": disciplines,
            "paginas_analisadas": sorted(
                {
                    page
                    for _partial, source_pages in partials
                    for page in source_pages
                }
            ),
        }
        if disciplines:
            document.status = "ready"
            document.progress = 100
            document.error_code = None
            document.error_message = None
        else:
            document.status = "needs_review"
            document.progress = 95
            document.error_code = "subjects_not_found"
            document.error_message = (
                "Nao foi possivel confirmar disciplinas com evidencia. "
                "Revise o cargo antes de tentar novamente."
            )
        document.updated_at = _now()
        _finish_job(
            db,
            job,
            result={
                "window_count": len(windows),
                "subject_count": len(disciplines),
                "checkpoint_version": ANALYSIS_CHECKPOINT_VERSION,
                "checkpoints": checkpoints,
            },
        )
    except Exception as exc:
        logger.exception(
            "study_document_analysis_failed",
            extra={"document_id": document.id, "job_id": job.id},
        )
        _fail_job(db, job, document, exc)


def serialize_job_payload(value: dict[str, Any] | None) -> str:
    return json.dumps(value or {}, ensure_ascii=False, separators=(",", ":"))
