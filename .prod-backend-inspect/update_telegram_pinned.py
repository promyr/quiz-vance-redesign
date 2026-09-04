from __future__ import annotations

import json

from app import telegram_bot


CHAT_ID = "-1003742591996"
MESSAGE_ID = 75
EXPECTED_HOST = "github.com/promyr/quiz-vance-redesign"

download_url = telegram_bot.download_url()
if EXPECTED_HOST not in download_url:
    raise RuntimeError("refusing to publish a non-canonical download URL")

text = "\n".join(
    [
        "Link oficial de download do Quiz Vance",
        f"Baixe o app apenas por este link: {download_url}",
        "Se voce encontrou um link antigo do Drive ou do backend anterior, desconsidere.",
        "Depois de instalar, abra o app e toque em Criar conta/Cadastrar.",
    ]
)

client = telegram_bot.TelegramBotClient()
updated = dict(
    client.request(
        "editMessageText",
        {
            "chat_id": CHAT_ID,
            "message_id": MESSAGE_ID,
            "text": text,
            "reply_markup": telegram_bot.default_reply_markup(),
        },
    )
    or {}
)

keyboard = dict(updated.get("reply_markup") or {}).get("inline_keyboard") or []
urls = [
    button.get("url")
    for row in keyboard
    for button in row
    if isinstance(button, dict) and button.get("url")
]
if download_url not in urls:
    raise RuntimeError("updated Telegram keyboard does not contain the canonical download URL")

print(
    json.dumps(
        {
            "ok": True,
            "message_id": updated.get("message_id"),
            "download_url": download_url,
            "button_updated": True,
        }
    )
)
