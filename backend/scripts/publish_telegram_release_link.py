from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path
from urllib.parse import urlparse

import httpx
from sqlalchemy import text

sys.path.insert(0, "/app")

from app import telegram_bot
from app.database import SessionLocal

VERSION = "2.0.36+35"
EXPECTED_HOST = "quiz-vance-redesign-backend.fly.dev"
APK_PATH = Path("/app/releases/android/quiz-vance.apk")


def _community_target() -> tuple[str, int | None]:
    with SessionLocal() as db:
        row = (
            db.execute(
                text(
                    """
                SELECT chat_id, comece_aqui_thread_id
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
    thread_id = row["comece_aqui_thread_id"]
    return str(row["chat_id"]), int(thread_id) if thread_id is not None else None


def _release_metadata() -> tuple[str, int, str]:
    url = telegram_bot.download_url()
    parsed = urlparse(url)
    if parsed.scheme != "https" or parsed.hostname != EXPECTED_HOST:
        raise RuntimeError("refusing to publish a non-canonical download URL")
    if not APK_PATH.is_file():
        raise RuntimeError("release APK was not found in the deployed image")
    size = APK_PATH.stat().st_size
    digest = hashlib.sha256(APK_PATH.read_bytes()).hexdigest().upper()
    return url, size, digest


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


def main() -> None:
    chat_id, thread_id = _community_target()
    download_url, size, digest = _release_metadata()
    _verify_remote_release(
        download_url,
        expected_size=size,
        expected_sha256=digest,
    )
    text_body = "\n".join(
        [
            f"Quiz Vance {VERSION} — APK oficial para teste",
            "",
            f"Baixe somente por este link: {download_url}",
            f"Tamanho: {size:,} bytes".replace(",", "."),
            f"SHA-256: {digest}",
            "",
            (
                "Esta versão corrige o login administrativo, o fluxo de geração "
                "com fallback, quotas, caracteres UTF-8 e o download incompleto."
            ),
            "Links e APKs antigos devem ser desconsiderados.",
        ]
    )
    keyboard = telegram_bot.default_reply_markup()
    client = telegram_bot.TelegramBotClient()
    chat = dict(client.request("getChat", {"chat_id": chat_id}) or {})
    pinned = dict(chat.get("pinned_message") or {})
    pinned_id = pinned.get("message_id")

    updated: dict[str, object]
    mode = "edited"
    if pinned_id:
        try:
            updated = dict(
                client.request(
                    "editMessageText",
                    {
                        "chat_id": chat_id,
                        "message_id": int(pinned_id),
                        "text": text_body,
                        "reply_markup": keyboard,
                    },
                )
                or {}
            )
        except (telegram_bot.TelegramBotError, httpx.HTTPError):
            mode = "replaced"
            updated = client.send_message(
                chat_id,
                text_body,
                message_thread_id=thread_id,
                reply_markup=keyboard,
            )
            client.pin_chat_message(chat_id, int(updated["message_id"]))
    else:
        mode = "created"
        updated = client.send_message(
            chat_id,
            text_body,
            message_thread_id=thread_id,
            reply_markup=keyboard,
        )
        client.pin_chat_message(chat_id, int(updated["message_id"]))

    verified_chat = dict(client.request("getChat", {"chat_id": chat_id}) or {})
    verified_pinned = dict(verified_chat.get("pinned_message") or {})
    verified_markup = dict(verified_pinned.get("reply_markup") or {})
    urls = [
        button.get("url")
        for row in verified_markup.get("inline_keyboard") or []
        for button in row
        if isinstance(button, dict) and button.get("url")
    ]
    if download_url not in urls or download_url not in str(
        verified_pinned.get("text") or ""
    ):
        raise RuntimeError("Telegram pinned message verification failed")

    print(
        json.dumps(
            {
                "ok": True,
                "mode": mode,
                "chat_id": chat_id,
                "message_id": verified_pinned.get("message_id"),
                "download_url": download_url,
                "apk_size": size,
                "sha256": digest,
            },
            ensure_ascii=True,
        )
    )


if __name__ == "__main__":
    main()
