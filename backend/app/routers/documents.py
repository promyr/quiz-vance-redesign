from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Literal

from fastapi import (
    APIRouter,
    Depends,
    File,
    Form,
    Header,
    HTTPException,
    Query,
    Response,
    UploadFile,
)
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from .. import models
from ..database import get_db
from ..deps import require_user
from ..document_processing import (
    MAX_PDF_BYTES,
)
from ..document_storage import DocumentStorage, DocumentStorageError
from ..rate_limit import rate_limit

router = APIRouter(prefix="/v2/documents", tags=["documents-v2"])


class SelectCargoIn(BaseModel):
    cargo_id: str = Field(min_length=1, max_length=120)


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _document_for_user(
    db: Session,
    *,
    document_id: int,
    user_id: int,
    for_update: bool = False,
) -> models.StudyDocument:
    query = (
        db.query(models.StudyDocument)
        .filter(
            models.StudyDocument.id == int(document_id),
            models.StudyDocument.user_id == int(user_id),
        )
    )
    if for_update:
        query = query.with_for_update()
    document = query.first()
    if document is None:
        raise HTTPException(status_code=404, detail="Documento nao encontrado.")
    return document


def _serialize_document(
    document: models.StudyDocument,
    *,
    include_result: bool = True,
) -> dict[str, Any]:
    can_retry = bool(
        document.purpose == "study_plan"
        and document.status == "failed"
        and document.page_count
        and document.selected_cargo_id
        and document.selected_cargo_title
    )
    return {
        "id": int(document.id),
        "purpose": str(document.purpose),
        "file_name": str(document.file_name),
        "size_bytes": int(document.size_bytes),
        "status": str(document.status),
        "progress": max(0, min(100, int(document.progress or 0))),
        "page_count": (
            int(document.page_count) if document.page_count is not None else None
        ),
        "cargos": list(document.cargos or []),
        "exam_date": document.exam_date,
        "selected_cargo_id": document.selected_cargo_id,
        "selected_cargo_title": document.selected_cargo_title,
        "analysis_result": document.analysis_result if include_result else None,
        "can_retry": can_retry,
        "error": (
            {
                "code": document.error_code,
                "message": document.error_message,
            }
            if document.error_code or document.error_message
            else None
        ),
        "created_at": document.created_at.isoformat()
        if document.created_at
        else None,
        "updated_at": document.updated_at.isoformat()
        if document.updated_at
        else None,
    }


@router.post(
    "",
    status_code=201,
    dependencies=[Depends(rate_limit(10, 60))],
)
async def upload_document(
    purpose: Literal["study_plan", "library"] = Form(...),
    file: UploadFile = File(...),
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = require_user(authorization, db)
    storage = DocumentStorage.from_environment()
    try:
        stored = await storage.save_pdf(
            file_name=file.filename or "documento.pdf",
            content_type=file.content_type,
            read=file.read,
            max_bytes=MAX_PDF_BYTES,
        )
    except DocumentStorageError as exc:
        raise HTTPException(status_code=exc.status_code, detail=str(exc)) from exc

    try:
        document = models.StudyDocument(
            user_id=user.id,
            purpose=purpose,
            file_name=stored.file_name,
            content_type="application/pdf",
            size_bytes=stored.size_bytes,
            sha256=stored.sha256,
            storage_key=stored.storage_key,
            pdf_bytes=None,
            status="extracting",
            progress=0,
            cargos=[],
        )
        db.add(document)
        db.flush()
        db.add(
            models.StudyDocumentJob(
                document_id=document.id,
                user_id=user.id,
                kind="extract",
                status="queued",
                progress=0,
                attempt_count=0,
                available_at=_now(),
            )
        )
        db.commit()
    except Exception:
        db.rollback()
        storage.delete(stored.storage_key)
        raise
    db.refresh(document)
    return _serialize_document(document, include_result=False)


@router.get("")
def list_documents(
    purpose: Literal["study_plan", "library"] | None = Query(default=None),
    limit: int = Query(default=50, ge=1, le=100),
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = require_user(authorization, db)
    query = db.query(models.StudyDocument).filter(
        models.StudyDocument.user_id == user.id
    )
    if purpose is not None:
        query = query.filter(models.StudyDocument.purpose == purpose)
    rows = (
        query.order_by(models.StudyDocument.created_at.desc())
        .limit(int(limit))
        .all()
    )
    return {
        "items": [
            _serialize_document(row, include_result=False) for row in rows
        ]
    }


@router.get("/{document_id}")
def get_document(
    document_id: int,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = require_user(authorization, db)
    return _serialize_document(
        _document_for_user(db, document_id=document_id, user_id=user.id)
    )


@router.get("/{document_id}/content")
def get_document_content(
    document_id: int,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = require_user(authorization, db)
    document = _document_for_user(
        db, document_id=document_id, user_id=user.id
    )
    if document.status != "ready":
        raise HTTPException(
            status_code=409,
            detail="O documento ainda nao terminou de processar.",
        )
    if document.purpose != "library":
        raise HTTPException(
            status_code=422,
            detail="Conteudo integral disponivel somente para a biblioteca.",
        )
    return {
        "document_id": document.id,
        "text": str(document.extracted_text or ""),
        "page_count": document.page_count,
    }


@router.post(
    "/{document_id}/select-cargo",
    status_code=202,
    dependencies=[Depends(rate_limit(20, 60))],
)
def select_document_cargo(
    document_id: int,
    payload: SelectCargoIn,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = require_user(authorization, db)
    document = _document_for_user(
        db, document_id=document_id, user_id=user.id
    )
    if document.purpose != "study_plan":
        raise HTTPException(
            status_code=422,
            detail="Selecao de cargo disponivel somente para editais.",
        )
    cargo = next(
        (
            item
            for item in list(document.cargos or [])
            if str(item.get("id") or "") == payload.cargo_id
        ),
        None,
    )
    if cargo is None:
        raise HTTPException(
            status_code=422,
            detail="Cargo nao pertence ao edital processado.",
        )

    active = (
        db.query(models.StudyDocumentJob)
        .filter(
            models.StudyDocumentJob.document_id == document.id,
            models.StudyDocumentJob.kind == "analyze",
            models.StudyDocumentJob.status.in_(
                ("queued", "running", "retrying")
            ),
        )
        .first()
    )
    cargo_title = str(cargo.get("title") or "").strip()
    if active is None:
        db.add(
            models.StudyDocumentJob(
                document_id=document.id,
                user_id=user.id,
                kind="analyze",
                status="queued",
                progress=0,
                attempt_count=0,
                payload={
                    "cargo_id": payload.cargo_id,
                    "cargo_title": cargo_title,
                },
                available_at=_now(),
            )
        )
    else:
        active.payload = {
            "cargo_id": payload.cargo_id,
            "cargo_title": cargo_title,
        }
        active.status = "queued"
        active.available_at = _now()
        active.locked_by = None
        active.locked_until = None
        active.error_code = None
        active.error_message = None
        active.updated_at = _now()

    document.selected_cargo_id = payload.cargo_id
    document.selected_cargo_title = cargo_title
    document.analysis_result = None
    document.status = "analyzing"
    document.progress = 60
    document.error_code = None
    document.error_message = None
    document.updated_at = _now()
    db.commit()
    db.refresh(document)
    return _serialize_document(document)


@router.post(
    "/{document_id}/retry-analysis",
    status_code=202,
    dependencies=[Depends(rate_limit(10, 60))],
)
def retry_document_analysis(
    document_id: int,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = require_user(authorization, db)
    document = _document_for_user(
        db,
        document_id=document_id,
        user_id=user.id,
        for_update=True,
    )
    if document.purpose != "study_plan":
        raise HTTPException(
            status_code=422,
            detail="Retomada de analise disponivel somente para editais.",
        )
    if not document.selected_cargo_id or not document.selected_cargo_title:
        raise HTTPException(
            status_code=409,
            detail="Selecione um cargo antes de retomar a analise.",
        )
    has_pages = (
        db.query(models.StudyDocumentPage.id)
        .filter(models.StudyDocumentPage.document_id == document.id)
        .first()
        is not None
    )
    if not has_pages:
        raise HTTPException(
            status_code=409,
            detail="As paginas extraidas nao estao mais disponiveis.",
        )

    active = (
        db.query(models.StudyDocumentJob)
        .filter(
            models.StudyDocumentJob.document_id == document.id,
            models.StudyDocumentJob.kind == "analyze",
            models.StudyDocumentJob.status.in_(
                ("queued", "running", "retrying")
            ),
        )
        .order_by(models.StudyDocumentJob.id.desc())
        .first()
    )
    if active is not None:
        if document.status != "analyzing":
            document.status = "analyzing"
            document.error_code = None
            document.error_message = None
            document.updated_at = _now()
            db.commit()
            db.refresh(document)
        return _serialize_document(document)

    if document.status != "failed":
        raise HTTPException(
            status_code=409,
            detail="Este edital nao possui uma analise com falha para retomar.",
        )

    job = (
        db.query(models.StudyDocumentJob)
        .filter(
            models.StudyDocumentJob.document_id == document.id,
            models.StudyDocumentJob.kind == "analyze",
        )
        .order_by(models.StudyDocumentJob.id.desc())
        .first()
    )
    payload = {
        "cargo_id": document.selected_cargo_id,
        "cargo_title": document.selected_cargo_title,
    }
    if job is None:
        job = models.StudyDocumentJob(
            document_id=document.id,
            user_id=user.id,
            kind="analyze",
            payload=payload,
        )
        db.add(job)
    job.payload = payload
    job.status = "queued"
    job.progress = 0
    job.attempt_count = 0
    job.available_at = _now()
    job.locked_by = None
    job.locked_until = None
    job.error_code = None
    job.error_message = None
    job.updated_at = _now()

    document.status = "analyzing"
    document.progress = max(60, int(document.progress or 0))
    document.analysis_result = None
    document.error_code = None
    document.error_message = None
    document.updated_at = _now()
    db.commit()
    db.refresh(document)
    return _serialize_document(document)


@router.delete("/{document_id}", status_code=204)
def delete_document(
    document_id: int,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
):
    user = require_user(authorization, db)
    document = _document_for_user(
        db, document_id=document_id, user_id=user.id
    )
    storage_key = document.storage_key
    db.query(models.StudyDocumentPage).filter(
        models.StudyDocumentPage.document_id == document.id
    ).delete(synchronize_session=False)
    db.query(models.StudyDocumentJob).filter(
        models.StudyDocumentJob.document_id == document.id
    ).delete(synchronize_session=False)
    db.delete(document)
    db.commit()
    DocumentStorage.from_environment().delete(storage_key)
    return Response(status_code=204)
