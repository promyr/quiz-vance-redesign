from __future__ import annotations

import os
from unittest.mock import patch

from app import telegram_bot


TELEGRAM_URL = "https://quiz-vance-redesign-backend.fly.dev/app/download/android/latest.apk"
STALE_ANDROID_URL = "https://quiz-vance-backend.fly.dev/app/download/android/latest.apk"


def test_telegram_download_url_is_the_canonical_source() -> None:
    with patch.dict(
        os.environ,
        {
            "TELEGRAM_DOWNLOAD_URL": TELEGRAM_URL,
            "ANDROID_APP_DOWNLOAD_URL": STALE_ANDROID_URL,
        },
    ):
        assert telegram_bot.download_url() == TELEGRAM_URL

        keyboard = telegram_bot.default_reply_markup()["inline_keyboard"]
        download_button = next(row[0] for row in keyboard if row[0]["text"] == "Baixar app")
        assert download_button["url"] == TELEGRAM_URL

        comece_aqui = next(
            topic for topic in telegram_bot.DEFAULT_GROUP_BLUEPRINT if topic.key == "comece_aqui"
        )
        assert TELEGRAM_URL in telegram_bot._topic_starter_text(comece_aqui)


if __name__ == "__main__":
    test_telegram_download_url_is_the_canonical_source()
    print("telegram download configuration: OK")
