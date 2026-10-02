"""Regression coverage for ciphertext written before the KDF change."""

import base64

import pytest
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

from app import security, services


def legacy_ciphertext(secret: str, *, salt: bytes | None, info: bytes) -> str:
    key = HKDF(algorithm=hashes.SHA256(), length=32, salt=salt, info=info).derive(
        secret.encode()
    )
    token = Fernet(base64.urlsafe_b64encode(key)).encrypt(b"provider-test-value")
    return "enc:v1:" + token.decode()


@pytest.mark.parametrize(
    ("salt", "info"),
    [
        (None, b"quiz-vance:user-settings:api-keys:v1"),
        (b"quiz-vance-hkdf-salt-v1", b"quiz-vance:user-settings"),
        (b"custom-salt-long-enough", b"quiz-vance:user-settings"),
    ],
)
def test_reads_all_historical_v1_derivations(monkeypatch, salt, info):
    monkeypatch.setenv("DATA_ENCRYPTION_SALT", "custom-salt-long-enough")
    encrypted = legacy_ciphertext("original-key", salt=salt, info=info)
    assert security.decrypt_secret("original-key", encrypted) == "provider-test-value"


def test_new_envelope_is_independent_of_environment_salt(monkeypatch):
    monkeypatch.setenv("DATA_ENCRYPTION_SALT", "old-salt-long-enough")
    encrypted = security.encrypt_secret("test-key", "provider-test-value")
    assert encrypted.startswith("enc:v2:")
    monkeypatch.setenv("DATA_ENCRYPTION_SALT", "changed-salt-long-enough")
    assert security.decrypt_secret("test-key", encrypted) == "provider-test-value"
    assert security.encrypt_secret("test-key", encrypted) == encrypted


def test_legacy_ciphertext_can_be_reencrypted_with_new_envelope():
    old = legacy_ciphertext(
        "test-key", salt=None, info=b"quiz-vance:user-settings:api-keys:v1"
    )
    upgraded = security.encrypt_secret("test-key", old)
    assert upgraded.startswith("enc:v2:")
    assert security.decrypt_secret("test-key", upgraded) == "provider-test-value"


def test_previous_master_key_and_legacy_derivation_work_together(monkeypatch):
    monkeypatch.setenv("DATA_ENCRYPTION_KEY", "new-key")
    monkeypatch.setenv("DATA_ENCRYPTION_PREVIOUS_KEYS", "old-key")
    encrypted = legacy_ciphertext(
        "old-key", salt=None, info=b"quiz-vance:user-settings:api-keys:v1"
    )
    assert services.decrypt_api_key("session-key", encrypted) == "provider-test-value"


@pytest.mark.parametrize("encrypted", ["enc:v2:malformed", "enc:v99:unknown"])
def test_invalid_envelope_is_never_treated_as_plaintext(encrypted):
    with pytest.raises(ValueError, match="secret_decryption_failed"):
        security.decrypt_secret("test-key", encrypted)


def test_wrong_key_does_not_leak_or_decrypt_ciphertext():
    encrypted = security.encrypt_secret("original-key", "provider-test-value")
    with pytest.raises(ValueError, match="secret_decryption_failed"):
        security.decrypt_secret("wrong-key", encrypted)
