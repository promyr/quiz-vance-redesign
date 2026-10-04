from __future__ import annotations

import base64
import logging
import os

from cryptography.fernet import Fernet, InvalidToken
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

SECRET_PREFIX = "enc:v2:"
SECRET_PREFIX_V1 = "enc:v1:"
SECRET_PREFIX_V2 = "enc:v2:"

_V2_HKDF_INFO = b"quiz-vance:secrets:v2"
_V1_HISTORICAL_DERIVATIONS = (
    (None, b"quiz-vance:user-settings:api-keys:v1"),
    (b"quiz-vance-hkdf-salt-v1", b"quiz-vance:user-settings"),
)


def _derive_fernet_v2(secret: str, salt: bytes) -> Fernet:
    key = HKDF(
        algorithm=hashes.SHA256(),
        length=32,
        salt=salt,
        info=_V2_HKDF_INFO,
    ).derive(secret.encode("utf-8"))
    return Fernet(base64.urlsafe_b64encode(key))


def is_encrypted_secret(value: str | None) -> bool:
    raw = str(value or "").strip()
    return raw.startswith("enc:")


def encrypt_secret(app_secret: str, value: str | None) -> str | None:
    raw = str(value or "").strip()
    if not raw:
        return None
    secret = str(app_secret or "").strip()
    if not secret:
        raise RuntimeError("app_secret_missing")

    # Se já é um v2 válido, retorna idempotente
    if raw.startswith(SECRET_PREFIX_V2):
        return raw

    # Se é um segredo cifrado legado (ex: v1), decripta primeiro para atualizar para v2
    if is_encrypted_secret(raw):
        plaintext = decrypt_secret(secret, raw)
        if plaintext is None:
            return None
        raw = plaintext

    salt = os.urandom(16)
    fernet = _derive_fernet_v2(secret, salt)
    token = fernet.encrypt(raw.encode("utf-8"))
    payload = base64.urlsafe_b64encode(salt + token).decode("ascii")
    return f"{SECRET_PREFIX_V2}{payload}"


def decrypt_secret(app_secret: str, value: str | None) -> str | None:
    raw = str(value or "").strip()
    if not raw:
        return None
    if not is_encrypted_secret(raw):
        return raw

    secret = str(app_secret or "").strip()
    if not secret:
        raise RuntimeError("app_secret_missing")

    if raw.startswith(SECRET_PREFIX_V2):
        body = raw[len(SECRET_PREFIX_V2) :]
        try:
            raw_bytes = base64.urlsafe_b64decode(body.encode("ascii"))
            if len(raw_bytes) < 17:
                raise ValueError("secret_decryption_failed")
            salt = raw_bytes[:16]
            token = raw_bytes[16:]
            fernet = _derive_fernet_v2(secret, salt)
            decrypted = fernet.decrypt(token)
            return decrypted.decode("utf-8").strip() or None
        except Exception as exc:
            raise ValueError("secret_decryption_failed") from exc

    if raw.startswith(SECRET_PREFIX_V1):
        token_str = raw[len(SECRET_PREFIX_V1) :]
        token = token_str.encode("ascii")

        salt_env = os.getenv("DATA_ENCRYPTION_SALT", "").encode("utf-8")
        derivations = list(_V1_HISTORICAL_DERIVATIONS)
        if len(salt_env) >= 16:
            derivations.append((salt_env, b"quiz-vance:user-settings"))

        for salt, info in derivations:
            try:
                key = HKDF(
                    algorithm=hashes.SHA256(),
                    length=32,
                    salt=salt,
                    info=info,
                ).derive(secret.encode("utf-8"))
                decrypted = Fernet(base64.urlsafe_b64encode(key)).decrypt(token)
                return decrypted.decode("utf-8").strip() or None
            except (InvalidToken, ValueError):
                logging.getLogger(__name__).debug("Legacy encryption derivation did not match")
                continue
        raise ValueError("secret_decryption_failed")

    # Qualquer envelope não suportado (ex: enc:v99:) deve falhar explicitamente
    raise ValueError("secret_decryption_failed")
