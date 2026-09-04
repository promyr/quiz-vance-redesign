from __future__ import annotations

import hashlib
import hmac
import json
import os
import sys
from pathlib import Path
from urllib.parse import urlparse

import httpx
from sqlalchemy import text

sys.path.insert(0, "/app")

from app import telegram_bot
from app.database import SessionLocal

EXPECTED_HOST = "quiz-vance-redesign-backend.fly.dev"
APK_PATH = Path("/app/releases/android/quiz-vance.apk")


def _release_version() -> str:
    version = str(os.getenv("RELEASE_VERSION") or "").strip()
    if not version:
        raise RuntimeError("RELEASE_VERSION must be configured for Telegram publication")
    return version


def _community_target() -> tuple[str, int]:
    with SessionLocal() as db:
        row = (
            db.execute(
                text(
                    """
                SELECT chat_id, atualizacoes_thread_id
                FROM telegram_community_config
                ORDER BY updated_at DESC, id DESC
                LIMIT 1
                """
                )
            )
            .mappings()
            .first()
        )
    if not row:
        raise RuntimeError("telegram community configuration was not found")
    thread_id = int(row["atualizacoes_thread_id"] or 0)
    if thread_id <= 0:
        raise RuntimeError("Telegram Updates topic was not configured")
    return str(row["chat_id"]), thread_id


def _release_metadata(version: str) -> tuple[str, int, str]:
    url = telegram_bot.download_url()
    parsed = urlparse(url)
    if parsed.scheme != "https" or parsed.hostname != EXPECTED_HOST:
        raise RuntimeError("refusing to publish a non-canonical download URL")
    if not APK_PATH.is_file():
        raise RuntimeError("release APK was not found in the deployed image")
    versioned_path = APK_PATH.with_name(f"quiz-vance-{version}.apk")
    if not versioned_path.is_file():
        raise RuntimeError("versioned release APK is missing from the deployed image")
    size = APK_PATH.stat().st_size
    digest = hashlib.sha256()
    with APK_PATH.open("rb") as artifact:
        for chunk in iter(lambda: artifact.read(1024 * 1024), b""):
            digest.update(chunk)
    sha256 = digest.hexdigest().upper()
    if versioned_path.stat().st_size != size:
        raise RuntimeError("latest and versioned release APK sizes do not match")
    return url, size, sha256


def _verify_remote_release(
    download_url: str,
    *,
    expected_size: int,
    expected_sha256: str,
    client: httpx.Client | None = None,
) -> tuple[int, str]:
    owns_client = client is None
    http_client = client or httpx.Client(
        timeout=httpx.Timeout(300.0),
        follow_redirects=True,
    )
    size = 0
    digest = hashlib.sha256()
    try:
        with http_client.stream("GET", download_url) as response:
            response.raise_for_status()
            for chunk in response.iter_bytes():
                size += len(chunk)
                digest.update(chunk)
    finally:
        if owns_client:
            http_client.close()

    sha256 = digest.hexdigest().upper()
    if size != int(expected_size) or sha256 != str(expected_sha256).upper():
        raise RuntimeError(
            "public release size or SHA-256 does not match local artifact"
        )
    return size, sha256


def _operator_attestation_matches(
    *,
    expected_size: int,
    expected_sha256: str,
) -> bool:
    raw_size = str(os.getenv("RELEASE_PUBLIC_VERIFIED_SIZE") or "").strip()
    raw_sha256 = str(
        os.getenv("RELEASE_PUBLIC_VERIFIED_SHA256") or ""
    ).strip()
    if not raw_size or not raw_sha256:
        return False
    try:
        verified_size = int(raw_size)
    except ValueError:
        return False
    return verified_size == int(expected_size) and hmac.compare_digest(
        raw_sha256.upper(),
        str(expected_sha256).upper(),
    )


def _validate_uploaded_apk(
    message: dict[str, object],
    *,
    expected_size: int,
    expected_thread_id: int,
) -> None:
    document = dict(message.get("document") or {})
    filename = str(document.get("file_name") or "").strip().lower()
    if not filename.endswith(".apk"):
        raise RuntimeError("Telegram did not return an APK document")
    if int(document.get("file_size") or 0) != int(expected_size):
        raise RuntimeError("Telegram APK size does not match the release artifact")
    if int(message.get("message_thread_id") or 0) != int(expected_thread_id):
        raise RuntimeError("Telegram APK was published to the wrong topic")
    if int(message.get("message_id") or 0) <= 0:
        raise RuntimeError("Telegram did not return a valid message id")


def _release_caption(*, version: str, size: int, digest: str) -> str:
    return "\n".join(
        [
            f"Quiz Vance {version} — APK oficial para teste",
            "",
            f"Tamanho: {size:,} bytes".replace(",", "."),
            f"SHA-256: {digest}",
            "",
            (
                "Nova Central de Editais: o PDF fica salvo de forma privada, "
                "é processado em segundo plano e você pode retomar sem reenvio."
            ),
            (
                "A análise divide segmentos grandes, retoma checkpoints e alterna "
                "entre provedores em limite temporário."
            ),
            "A extração percorre todas as páginas e usa OCR seletivo quando necessário.",
            "A Biblioteca também usa o mesmo pipeline confiável de PDF.",
            (
                "Biometria de login corrigida: a digital só aparece quando o cofre "
                "biométrico estiver realmente configurado."
            ),
            "Toque no arquivo acima para baixar e instalar.",
        ]
    )


def main() -> None:
    version = _release_version()
    chat_id, thread_id = _community_target()
    download_url, size, digest = _release_metadata(version)
    if not _operator_attestation_matches(
        expected_size=size,
        expected_sha256=digest,
    ):
        _verify_remote_release(
            download_url,
            expected_size=size,
            expected_sha256=digest,
        )
    caption = _release_caption(
        version=version,
        size=size,
        digest=digest,
    )
    client = telegram_bot.TelegramBotClient(timeout_seconds=600.0)
    uploaded = client.send_document(
        chat_id,
        APK_PATH,
        caption=caption,
        filename=f"quiz-vance-{version}.apk",
        message_thread_id=thread_id,
    )
    _validate_uploaded_apk(
        uploaded,
        expected_size=size,
        expected_thread_id=thread_id,
    )

    print(
        json.dumps(
            {
                "ok": True,
                "mode": "apk_attached",
                "chat_id": chat_id,
                "message_thread_id": thread_id,
                "message_id": uploaded.get("message_id"),
                "download_url": download_url,
                "apk_size": size,
                "sha256": digest,
            },
            ensure_ascii=True,
        )
    )


if __name__ == "__main__":
    main()
