from __future__ import annotations

import base64

from cryptography.fernet import Fernet, InvalidToken
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

SECRET_PREFIX = "enc:v1:"
_HKDF_INFO = b"quiz-vance:user-settings"


_HKDF_SALT = b"quiz-vance-hkdf-salt-v1"


def _derive_fernet(app_secret: str) -> Fernet:
    secret = str(app_secret or "").strip()
    if not secret:
        raise RuntimeError("app_secret_missing")

    salt_env = os.getenv("DATA_ENCRYPTION_SALT", "").encode("utf-8")
    salt = salt_env if len(salt_env) >= 16 else _HKDF_SALT

    key = HKDF(
        algorithm=hashes.SHA256(),
        length=32,
        salt=salt,
        info=_HKDF_INFO,
    ).derive(secret.encode("utf-8"))
    return Fernet(base64.urlsafe_b64encode(key))


def is_encrypted_secret(value: str | None) -> bool:
    raw = str(value or "").strip()
    return raw.startswith(SECRET_PREFIX)


def encrypt_secret(app_secret: str, value: str | None) -> str | None:
    raw = str(value or "").strip()
    if not raw:
        return None
    if is_encrypted_secret(raw):
        return raw

    token = _derive_fernet(app_secret).encrypt(raw.encode("utf-8")).decode("ascii")
    return f"{SECRET_PREFIX}{token}"


def decrypt_secret(app_secret: str, value: str | None) -> str | None:
    raw = str(value or "").strip()
    if not raw:
        return None
    if not is_encrypted_secret(raw):
        return raw

    token = raw[len(SECRET_PREFIX) :]
    try:
        decrypted = _derive_fernet(app_secret).decrypt(token.encode("ascii"))
    except InvalidToken as exc:
        raise ValueError("secret_decryption_failed") from exc

    return decrypted.decode("utf-8").strip() or None
