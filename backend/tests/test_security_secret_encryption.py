from __future__ import annotations

from app.security import decrypt_secret, encrypt_secret


def test_encrypt_secret_round_trip_uses_runtime_salt() -> None:
    encrypted = encrypt_secret("test-secret-at-least-32-bytes-long", "provider-key")

    assert encrypted is not None
    assert encrypted != "provider-key"
    assert (
        decrypt_secret("test-secret-at-least-32-bytes-long", encrypted)
        == "provider-key"
    )
