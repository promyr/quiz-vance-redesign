"""Real PDF upload/extraction and cargo selection, isolated DB/storage and JWT.

No provider call or OCR fixture is used; AI analysis is left queued.
"""

from io import BytesIO

import pytest
from pypdf import PdfWriter
from pypdf.generic import DecodedStreamObject, DictionaryObject, NameObject
from test_document_api import _account, _client, _database, _headers

from app import models
from app.document_processing import run_extraction_job


def study_pdf() -> bytes:
    writer = PdfWriter()
    font = writer._add_object(
        DictionaryObject(
            {
                NameObject("/Type"): NameObject("/Font"),
                NameObject("/Subtype"): NameObject("/Type1"),
                NameObject("/BaseFont"): NameObject("/Helvetica"),
            }
        )
    )
    for chapter, concept in [
        ("Adicao", "Dois mais dois resulta em quatro."),
        ("Fracoes", "Um meio representa metade de uma unidade."),
    ]:
        page = writer.add_blank_page(width=595, height=842)
        page[NameObject("/Resources")] = DictionaryObject(
            {NameObject("/Font"): DictionaryObject({NameObject("/F1"): font})}
        )
        stream = DecodedStreamObject()
        text = "BT /F1 12 Tf 40 780 Td "
        text += f"(CONTEUDO PROGRAMATICO: {chapter}) Tj "
        for _ in range(12):
            text += f"0 -20 Td ({concept} Revisar e resolver exercicios.) Tj "
        stream.set_data((text + "ET").encode("ascii"))
        page[NameObject("/Contents")] = writer._add_object(stream)
    output = BytesIO()
    writer.write(output)
    return output.getvalue()


@pytest.mark.parametrize("purpose", ["library", "study_plan"])
def test_student_uploads_real_pdf_and_reaches_reading_or_manual_cargo(
    purpose, monkeypatch, tmp_path
):
    monkeypatch.setenv("STUDY_DOCUMENT_STORAGE_ROOT", str(tmp_path))
    database = _database()
    db = next(database)
    try:
        owner = _account(db, f"student_{purpose}")
        other = _account(db, f"other_{purpose}")
        client = _client(db)
        response = client.post(
            "/v2/documents",
            headers=_headers(owner),
            data={"purpose": purpose},
            files={"file": ("matematica.pdf", study_pdf(), "application/pdf")},
        )
        assert response.status_code == 201, response.text
        document_id = response.json()["id"]
        assert (
            client.get(
                f"/v2/documents/{document_id}/content", headers=_headers(owner)
            ).status_code
            == 409
        )
        job = (
            db.query(models.StudyDocumentJob)
            .filter_by(document_id=document_id, kind="extract")
            .one()
        )
        run_extraction_job(db, job.id)
        db.expire_all()
        document = db.get(models.StudyDocument, document_id)
        assert document.page_count == 2
        assert "Dois mais dois" in document.extracted_text
        assert "metade de uma unidade" in document.extracted_text
        assert (
            db.query(models.StudyDocumentPage)
            .filter_by(document_id=document_id)
            .count()
            == 2
        )
        assert (
            client.get(
                f"/v2/documents/{document_id}", headers=_headers(other)
            ).status_code
            == 404
        )
        if purpose == "library":
            assert document.status == "ready"
            content = client.get(
                f"/v2/documents/{document_id}/content", headers=_headers(owner)
            )
            assert content.status_code == 200
            assert "Fracoes" in content.json()["text"]
        else:
            assert document.status == "needs_review"
            selected = client.post(
                f"/v2/documents/{document_id}/select-cargo",
                headers=_headers(owner),
                json={"cargo_id": "manual", "cargo_title": "Analista"},
            )
            assert selected.status_code == 202, selected.text
            db.expire_all()
            assert (
                db.get(models.StudyDocument, document_id).selected_cargo_title
                == "Analista"
            )
            assert (
                db.query(models.StudyDocumentJob)
                .filter_by(document_id=document_id, kind="analyze")
                .count()
                == 1
            )
    finally:
        database.close()
