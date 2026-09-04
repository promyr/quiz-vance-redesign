from __future__ import annotations

import hashlib
import os
import tempfile
import uuid
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


class DocumentStorageError(ValueError):
    def __init__(self, message: str, *, status_code: int = 422):
        super().__init__(message)
        self.status_code = status_code


@dataclass(frozen=True)
class StoredPdf:
    storage_key: str
    file_name: str
    size_bytes: int
    sha256: str


class DocumentStorage:
    """Armazena PDFs privados fora do banco usando escrita atomica."""

    def __init__(self, root: str | Path):
        self.root = Path(root).resolve()

    @classmethod
    def from_environment(cls) -> DocumentStorage:
        configured = str(os.getenv("STUDY_DOCUMENT_STORAGE_ROOT") or "").strip()
        root = configured or str(
            Path(tempfile.gettempdir()) / "quiz-vance-study-documents"
        )
        return cls(root)

    def _resolve(self, storage_key: str) -> Path:
        clean_key = str(storage_key or "").replace("\\", "/").lstrip("/")
        candidate = (self.root / clean_key).resolve()
        try:
            candidate.relative_to(self.root)
        except ValueError as exc:
            raise DocumentStorageError("Chave de armazenamento invalida.") from exc
        return candidate

    async def save_pdf(
        self,
        *,
        file_name: str,
        content_type: str | None,
        read: Callable[[int], Awaitable[bytes]],
        max_bytes: int,
    ) -> StoredPdf:
        safe_name = Path(str(file_name or "").replace("\\", "/")).name.strip()
        normalized_type = str(content_type or "").split(";", 1)[0].strip().lower()
        if not safe_name.lower().endswith(".pdf") or normalized_type not in {
            "",
            "application/pdf",
            "application/octet-stream",
        }:
            raise DocumentStorageError("Somente PDF e aceito.")

        incoming_dir = self.root / ".incoming"
        incoming_dir.mkdir(parents=True, exist_ok=True)
        partial_path = incoming_dir / f"{uuid.uuid4().hex}.part"
        digest = hashlib.sha256()
        prefix = bytearray()
        received = 0
        try:
            with partial_path.open("xb") as target:
                while True:
                    chunk = await read(1024 * 1024)
                    if not chunk:
                        break
                    received += len(chunk)
                    if received > int(max_bytes):
                        raise DocumentStorageError(
                            "O PDF excede o limite operacional de "
                            f"{int(max_bytes) // (1024 * 1024)} MiB.",
                            status_code=413,
                        )
                    if len(prefix) < 1024:
                        prefix.extend(chunk[: 1024 - len(prefix)])
                    digest.update(chunk)
                    target.write(chunk)

            if received <= 0:
                raise DocumentStorageError("PDF vazio.")
            if bytes(prefix).find(b"%PDF-") < 0:
                raise DocumentStorageError(
                    "PDF invalido: assinatura nao encontrada."
                )

            day_key = datetime.now(timezone.utc).strftime("%Y/%m/%d")
            storage_key = f"{day_key}/{uuid.uuid4().hex}.pdf"
            final_path = self._resolve(storage_key)
            final_path.parent.mkdir(parents=True, exist_ok=True)
            os.replace(partial_path, final_path)
            return StoredPdf(
                storage_key=storage_key,
                file_name=safe_name[:255] or "documento.pdf",
                size_bytes=received,
                sha256=digest.hexdigest(),
            )
        except Exception:
            partial_path.unlink(missing_ok=True)
            try:
                incoming_dir.rmdir()
            except OSError:
                pass
            raise

    def read(self, storage_key: str) -> bytes:
        path = self._resolve(storage_key)
        try:
            return path.read_bytes()
        except FileNotFoundError as exc:
            raise DocumentStorageError(
                "O PDF privado nao foi encontrado no armazenamento."
            ) from exc

    def delete(self, storage_key: str | None) -> None:
        if not storage_key:
            return
        path = self._resolve(storage_key)
        path.unlink(missing_ok=True)
