from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path

import httpx
from fastapi.testclient import TestClient

from app import main


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
        main,
        "_android_versioned_release_file_path",
        lambda version: str(apk) if version == "2.0.35" else "",
    )

    response = TestClient(main.app).head("/app/download/android/2.0.35.apk")

    assert response.status_code == 200
    assert response.headers["content-length"] == str(apk.stat().st_size)
    assert response.headers["accept-ranges"] == "bytes"
    assert response.content == b""


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
