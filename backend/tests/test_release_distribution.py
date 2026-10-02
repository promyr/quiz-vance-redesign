from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient

from app import main
from app.routers import releases


def _load_release_publisher():
    path = (
        Path(__file__).resolve().parents[1]
        / "scripts"
        / "publish_telegram_release_link.py"
    )
    spec = importlib.util.spec_from_file_location("release_publisher", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_versioned_apk_supports_head(monkeypatch, tmp_path: Path) -> None:
    apk = tmp_path / "quiz-vance-2.0.35.apk"
    apk.write_bytes(b"release-apk")
    monkeypatch.setattr(
        releases,
        "_android_versioned_release_file_path",
        lambda version: str(apk) if version == "2.0.35" else "",
    )

    response = TestClient(main.app).head("/app/download/android/2.0.35.apk")

    assert response.status_code == 200
    assert response.headers["content-length"] == str(apk.stat().st_size)
    assert response.headers["accept-ranges"] == "bytes"
    assert response.content == b""


def test_versioned_release_path_accepts_flutter_build_number() -> None:
    path = releases._android_versioned_release_file_path("2.0.51+50")

    assert path.endswith("quiz-vance-2.0.51+50.apk")


def test_remote_release_hash_must_match_public_download() -> None:
    publisher = _load_release_publisher()
    content = b"signed-release-apk"
    expected_digest = hashlib.sha256(content).hexdigest().upper()
    transport = httpx.MockTransport(
        lambda request: httpx.Response(
            200,
            headers={"Content-Length": str(len(content))},
            content=content,
            request=request,
        )
    )

    with httpx.Client(transport=transport) as client:
        size, digest = publisher._verify_remote_release(
            "https://quiz-vance-redesign-backend.fly.dev/app/download/android/latest.apk",
            expected_size=len(content),
            expected_sha256=expected_digest,
            client=client,
        )

    assert size == len(content)
    assert digest == expected_digest


def test_remote_release_hash_rejects_divergent_download() -> None:
    publisher = _load_release_publisher()
    expected_digest = hashlib.sha256(b"expected").hexdigest().upper()
    transport = httpx.MockTransport(
        lambda request: httpx.Response(200, content=b"different", request=request)
    )

    with httpx.Client(transport=transport) as client:
        try:
            publisher._verify_remote_release(
                "https://quiz-vance-redesign-backend.fly.dev/app/download/android/latest.apk",
                expected_size=len(b"expected"),
                expected_sha256=expected_digest,
                client=client,
            )
        except RuntimeError as exc:
            assert "public release" in str(exc).lower()
        else:
            raise AssertionError("hash público divergente deveria bloquear publicação")


def test_operator_attestation_requires_size_and_sha256(monkeypatch) -> None:
    publisher = _load_release_publisher()
    monkeypatch.delenv("RELEASE_PUBLIC_VERIFIED_SIZE", raising=False)
    monkeypatch.delenv("RELEASE_PUBLIC_VERIFIED_SHA256", raising=False)

    assert not publisher._operator_attestation_matches(
        expected_size=123,
        expected_sha256="ABCDEF",
    )


def test_operator_attestation_rejects_divergent_metadata(monkeypatch) -> None:
    publisher = _load_release_publisher()
    monkeypatch.setenv("RELEASE_PUBLIC_VERIFIED_SIZE", "122")
    monkeypatch.setenv("RELEASE_PUBLIC_VERIFIED_SHA256", "ABCDEF")

    assert not publisher._operator_attestation_matches(
        expected_size=123,
        expected_sha256="ABCDEF",
    )


def test_operator_attestation_accepts_exact_metadata(monkeypatch) -> None:
    publisher = _load_release_publisher()
    monkeypatch.setenv("RELEASE_PUBLIC_VERIFIED_SIZE", "123")
    monkeypatch.setenv("RELEASE_PUBLIC_VERIFIED_SHA256", "abcdef")

    assert publisher._operator_attestation_matches(
        expected_size=123,
        expected_sha256="ABCDEF",
    )


def test_uploaded_apk_must_match_expected_file_and_topic() -> None:
    publisher = _load_release_publisher()

    publisher._validate_uploaded_apk(
        {
            "message_id": 321,
            "message_thread_id": 44,
            "document": {
                "file_name": "quiz-vance-2.0.37.apk",
                "file_size": 123,
            },
        },
        expected_size=123,
        expected_thread_id=44,
    )


def test_release_caption_describes_durable_pdf_pipeline() -> None:
    publisher = _load_release_publisher()

    caption = publisher._release_caption(
        version="2.1.0",
        size=123,
        digest="ABCDEF",
    )

    assert "quiz vance" in caption.lower()
    assert "tamanho: 123 bytes" in caption.lower()
    assert "sha-256: abcdef" in caption.lower()
    assert "toque no arquivo acima para baixar e instalar." in caption.lower()


def test_uploaded_apk_rejects_wrong_topic() -> None:
    publisher = _load_release_publisher()

    try:
        publisher._validate_uploaded_apk(
            {
                "message_id": 321,
                "message_thread_id": 45,
                "document": {
                    "file_name": "quiz-vance-2.0.37.apk",
                    "file_size": 123,
                },
            },
            expected_size=123,
            expected_thread_id=44,
        )
    except RuntimeError as exc:
        assert "topic" in str(exc).lower()
    else:
        raise AssertionError("publicação no tópico errado deveria ser bloqueada")


def _local_release(publisher, monkeypatch, tmp_path, *, versioned=b"release"):
    apk = tmp_path / "quiz-vance.apk"
    apk.write_bytes(b"release")
    apk.with_name("quiz-vance-2.0.64+63.apk").write_bytes(versioned)
    monkeypatch.setattr(publisher, "APK_PATH", apk)
    monkeypatch.setattr(
        publisher.telegram_bot, "download_url",
        lambda: "https://quiz-vance-redesign-1.onrender.com/app/download/android/latest.apk",
    )
    manifest = {
        "app_version": "2.0.64+63",
        "backend_url": "https://quiz-vance-redesign-1.onrender.com",
        "apk_sha256": hashlib.sha256(b"release").hexdigest(),
        "size_bytes": 7,
        "certificate_sha256": "A" * 64,
    }
    manifest_path = tmp_path / "release-manifest.json"
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    return manifest_path, manifest


def test_metadata_accepts_canonical_render_and_matching_manifest(monkeypatch, tmp_path):
    publisher = _load_release_publisher()
    _local_release(publisher, monkeypatch, tmp_path)
    url, size, digest = publisher._release_metadata("2.0.64+63")
    assert "onrender.com" in url
    assert size == 7
    assert digest == hashlib.sha256(b"release").hexdigest().upper()


def test_metadata_rejects_same_size_different_versioned_apk(monkeypatch, tmp_path):
    publisher = _load_release_publisher()
    _local_release(publisher, monkeypatch, tmp_path, versioned=b"changed")
    with pytest.raises(RuntimeError, match="hash"):
        publisher._release_metadata("2.0.64+63")


def test_metadata_rejects_stale_manifest(monkeypatch, tmp_path):
    publisher = _load_release_publisher()
    path, manifest = _local_release(publisher, monkeypatch, tmp_path)
    manifest["app_version"] = "2.0.61+60"
    path.write_text(json.dumps(manifest), encoding="utf-8")
    with pytest.raises(RuntimeError, match="manifest"):
        publisher._release_metadata("2.0.64+63")


def test_uploaded_apk_rejects_wrong_chat_and_wrong_filename():
    publisher = _load_release_publisher()
    message = {
        "message_id": 321, "message_thread_id": 44,
        "chat": {"id": -100123},
        "document": {"file_name": "old.apk", "file_size": 123},
    }
    with pytest.raises(RuntimeError, match="filename"):
        publisher._validate_uploaded_apk(
            message, expected_size=123, expected_thread_id=44,
            expected_chat_id="-100123", expected_filename="quiz-vance-2.0.64+63.apk",
        )
    message["document"]["file_name"] = "quiz-vance-2.0.64+63.apk"
    with pytest.raises(RuntimeError, match="chat"):
        publisher._validate_uploaded_apk(
            message, expected_size=123, expected_thread_id=44,
            expected_chat_id="-100999", expected_filename="quiz-vance-2.0.64+63.apk",
        )
