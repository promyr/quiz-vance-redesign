from __future__ import annotations

import json

from app import telegram_bot


CHAT_ID = "-1003742591996"
MESSAGE_ID = 75
EXPECTED_URL = (
    "https://quiz-vance-redesign-backend.fly.dev/"
    "app/download/android/latest.apk"
)

download_url = telegram_bot.download_url()
if download_url != EXPECTED_URL:
    raise RuntimeError(f"unexpected Telegram download URL: {download_url}")

message_text = "\n".join(
    [
        "Link oficial de download do Quiz Vance",
        f"Baixe o app apenas por este link: {download_url}",
        "APK 2.0.11 corrigido, com aproximadamente 40 MB.",
        "Se houver um download antigo em 99%, cancele-o antes de tentar novamente.",
    ]
)

client = telegram_bot.TelegramBotClient()
updated = dict(
    client.request(
        "editMessageText",
        {
            "chat_id": CHAT_ID,
            "message_id": MESSAGE_ID,
            "text": message_text,
            "reply_markup": telegram_bot.default_reply_markup(),
        },
    )
    or {}
)

print(
    json.dumps(
        {
            "ok": True,
            "message_id": updated.get("message_id"),
            "download_url": download_url,
        }
    )
)
