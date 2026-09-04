from __future__ import annotations

import json

from app import telegram_bot


PUBLIC_BASE_URL = "https://quiz-vance-redesign-backend.fly.dev"
EXPECTED_WEBHOOK = f"{PUBLIC_BASE_URL}/telegram/webhook"

client = telegram_bot.TelegramBotClient()
telegram_bot.configure_webhook(
    client,
    PUBLIC_BASE_URL,
    drop_pending_updates=False,
)
info = dict(client.request("getWebhookInfo") or {})
if info.get("url") != EXPECTED_WEBHOOK:
    raise RuntimeError("Telegram webhook was not configured on the Redesign backend")

print(
    json.dumps(
        {
            "ok": True,
            "webhook_url": info.get("url"),
            "pending_update_count": info.get("pending_update_count", 0),
            "last_error_message": info.get("last_error_message"),
        }
    )
)
