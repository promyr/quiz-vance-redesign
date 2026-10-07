from test_document_api import _account, _client, _database, _headers

from app import models


def test_ready_edital_content_is_available_only_to_owner():
    db = next(_database())
    owner = _account(db, 'editalowner')
    other = _account(db, 'editalother')
    doc = models.StudyDocument(user_id=owner.id, purpose='study_plan',
        file_name='edital.pdf', content_type='application/pdf', size_bytes=12,
        sha256='a'*64, pdf_bytes=b'%PDF-1.7', status='ready', progress=100,
        extracted_text='Matemática: Frações e Porcentagens.', page_count=1)
    db.add(doc)
    db.commit()
    client = _client(db)
    response = client.get(f'/v2/documents/{doc.id}/content', headers=_headers(owner))
    assert response.status_code == 200
    assert 'Porcentagens' in response.json()['text']
    assert client.get(f'/v2/documents/{doc.id}/content', headers=_headers(other)).status_code == 404


def test_legacy_edital_recovers_existing_pages_in_document_order():
    db = next(_database())
    owner = _account(db, 'legacyowner')
    doc = models.StudyDocument(user_id=owner.id, purpose='study_plan',
        file_name='old.pdf', content_type='application/pdf', size_bytes=12,
        sha256='b'*64, status='ready', progress=100, page_count=2)
    db.add(doc)
    db.flush()
    for number, text in [(2, 'Porcentagens'), (1, 'Frações')]:
        db.add(models.StudyDocumentPage(document_id=doc.id, page_number=number,
            text=text, text_sha256='c'*64))
    db.commit()
    response = _client(db).get(f'/v2/documents/{doc.id}/content', headers=_headers(owner))
    assert response.status_code == 200
    assert response.json()['text'] == 'Frações\n\nPorcentagens'


def test_ready_document_without_extracted_artifact_requires_reprocessing():
    db = next(_database())
    owner = _account(db, 'emptyowner')
    doc = models.StudyDocument(user_id=owner.id, purpose='study_plan',
        file_name='missing.pdf', content_type='application/pdf', size_bytes=12,
        sha256='d'*64, status='ready', progress=100)
    db.add(doc)
    db.commit()
    response = _client(db).get(f'/v2/documents/{doc.id}/content', headers=_headers(owner))
    assert response.status_code == 409
