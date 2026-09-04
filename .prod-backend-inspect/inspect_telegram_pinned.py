from __future__ import annotations

import json

from sqlalchemy import text

from app.database import SessionLocal
from app.telegram_bot import TelegramBotClient


with SessionLocal() as db:
    config = db.execute(
        text(
            """
            SELECT chat_id, comece_aqui_thread_id
            FROM telegram_community_config
            ORDER BY updated_at DESC, id DESC
            LIMIT 1
            """
        )
    ).mappings().first()

if not config:
    raise RuntimeError("telegram community configuration was not found")

client = TelegramBotClient()
chat = dict(client.request("getChat", {"chat_id": config["chat_id"]}) or {})
pinned = dict(chat.get("pinned_message") or {})
keyboard = dict(pinned.get("reply_markup") or {}).get("inline_keyboard") or []
urls = [
    button.get("url")
    for row in keyboard
    for button in row
    if isinstance(button, dict) and button.get("url")
]

print(
    json.dumps(
        {
            "chat_id": str(config["chat_id"]),
            "comece_aqui_thread_id": config["comece_aqui_thread_id"],
            "pinned_message_id": pinned.get("message_id"),
            "pinned_message_thread_id": pinned.get("message_thread_id"),
            "pinned_text": pinned.get("text"),
            "pinned_urls": urls,
        },
        ensure_ascii=True,
    )
)
