"""Deprecated entrypoint kept to fail safely.

Telegram releases must use the server-side publisher, where credentials remain
in Fly secrets and the APK hash is verified before transmission.
"""

from __future__ import annotations


def main() -> None:
    raise SystemExit(
        "Deprecated insecure publisher. Use "
        "backend/scripts/publish_telegram_apk_attachment.py on the Fly backend."
    )


if __name__ == "__main__":
    main()
