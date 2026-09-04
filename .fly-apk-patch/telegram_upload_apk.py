from __future__ import annotations

import hashlib
import json
from pathlib import Path

import httpx

from app import telegram_bot


CHAT_ID = "-1003742591996"
APK_PATH = Path("/app/releases/android/quiz-vance.apk")
APK_FILENAME = "Quiz-Vance-2.0.12-caracteres-corrigidos.apk"
EXPECTED_SIZE = 41_551_922
EXPECTED_SHA256 = "00f986d77b5f1992b55b6d29e9abfcac77cd09e15ba40a4f8212b6ff0446a674"


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


if APK_PATH.stat().st_size != EXPECTED_SIZE:
    raise RuntimeError("refusing to upload an APK with an unexpected size")
if file_sha256(APK_PATH) != EXPECTED_SHA256:
    raise RuntimeError("refusing to upload an APK with an unexpected digest")

client = telegram_bot.TelegramBotClient()
caption = (
    "Quiz Vance 2.0.12 - caracteres corrigidos\n\n"
    "Este e o APK oficial enviado diretamente pelo Telegram. "
    "Acentos, emojis e simbolos do aplicativo foram reparados.\n\n"
    "Apague o APK anterior antes de instalar este arquivo."
)

with APK_PATH.open("rb") as apk_file:
    response = httpx.post(
        client._method_url("sendDocument"),
        data={"chat_id": CHAT_ID, "caption": caption},
        files={
            "document": (
                APK_FILENAME,
                apk_file,
                "application/vnd.android.package-archive",
            )
        },
        timeout=httpx.Timeout(300.0),
    )

response.raise_for_status()
payload = response.json()
if not payload.get("ok"):
    raise RuntimeError(payload.get("description") or "telegram_send_document_failed")

message = dict(payload.get("result") or {})
message_id = int(message["message_id"])
document = dict(message.get("document") or {})
if int(document.get("file_size") or 0) != EXPECTED_SIZE:
    raise RuntimeError("Telegram reported an unexpected uploaded file size")

client.pin_chat_message(CHAT_ID, message_id, disable_notification=True)
pinned = dict(client.request("getChat", {"chat_id": CHAT_ID}) or {}).get(
    "pinned_message"
) or {}
if int(pinned.get("message_id") or 0) != message_id:
    raise RuntimeError("the uploaded APK was not pinned")

print(
    json.dumps(
        {
            "ok": True,
            "message_id": message_id,
            "file_name": document.get("file_name"),
            "file_size": document.get("file_size"),
            "pinned": True,
        }
    )
)
