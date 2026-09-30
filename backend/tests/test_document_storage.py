from __future__ import annotations

import asyncio
from pathlib import Path

import pytest


def test_document_storage_streams_pdf_to_private_durable_path(
    tmp_path: Path,
) -> None:
    from app.document_storage import DocumentStorage

    content = b"\x00provider-prefix%PDF-1.7\n" + (b"x" * 4096)
    offset = 0

    async def read(size: int) -> bytes:
        nonlocal offset
        chunk = content[offset : offset + size]
        offset += len(chunk)
        return chunk

    storage = DocumentStorage(tmp_path)
    stored = asyncio.run(
        storage.save_pdf(
            file_name="edital.pdf",
            content_type="application/pdf",
            read=read,
            max_bytes=8192,
        )
    )

    assert stored.size_bytes == len(content)
    assert stored.storage_key.endswith(".pdf")
    assert storage.read(stored.storage_key) == content
    assert (tmp_path / stored.storage_key).is_file()


def test_document_storage_removes_partial_file_when_upload_is_invalid(
    tmp_path: Path,
) -> None:
    from app.document_storage import DocumentStorage, DocumentStorageError

    chunks = iter((b"not-a-pdf", b""))

    async def read(_size: int) -> bytes:
        return next(chunks)

    storage = DocumentStorage(tmp_path)

    with pytest.raises(DocumentStorageError, match="assinatura"):
        asyncio.run(
            storage.save_pdf(
                file_name="arquivo.pdf",
                content_type="application/pdf",
                read=read,
                max_bytes=8192,
            )
        )

    assert list(tmp_path.rglob("*")) == []


def test_cancelled_upload_removes_partial_file(tmp_path: Path) -> None:
    from app.document_storage import DocumentStorage

    async def read(_size: int) -> bytes:
        raise asyncio.CancelledError()

    with pytest.raises(asyncio.CancelledError):
        asyncio.run(DocumentStorage(tmp_path).save_pdf(
            file_name="edital.pdf", content_type="application/pdf",
            read=read, max_bytes=8192,
        ))
    assert list(tmp_path.rglob("*")) == []


def test_storage_creation_failure_is_safe_service_error(tmp_path: Path) -> None:
    from app.document_storage import DocumentStorage, DocumentStorageError

    root = tmp_path / "private"
    root.write_bytes(b"not a directory")

    async def read(_size: int) -> bytes:
        return b""

    with pytest.raises(DocumentStorageError) as caught:
        asyncio.run(DocumentStorage(root).save_pdf(
            file_name="edital.pdf", content_type="application/pdf",
            read=read, max_bytes=8192,
        ))
    assert caught.value.status_code == 503
    assert str(tmp_path) not in str(caught.value)


@pytest.mark.parametrize("key", ["", ".", "/file.pdf", "../file.pdf", "C:/file.pdf"])
def test_storage_rejects_non_relative_file_keys(tmp_path: Path, key: str) -> None:
    from app.document_storage import DocumentStorage, DocumentStorageError

    with pytest.raises(DocumentStorageError, match="Chave"):
        DocumentStorage(tmp_path).read(key)


def test_read_io_failure_is_retryable_and_sanitized(tmp_path: Path, monkeypatch) -> None:
    from app.document_storage import DocumentStorage, DocumentStorageError

    def denied(_path):
        raise PermissionError("private-volume/internal-path")

    monkeypatch.setattr(Path, "read_bytes", denied)
    with pytest.raises(DocumentStorageError) as caught:
        DocumentStorage(tmp_path).read("2026/test.pdf")
    assert caught.value.status_code == 503
    assert "private-volume" not in str(caught.value)
