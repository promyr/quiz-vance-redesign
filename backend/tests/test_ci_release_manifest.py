"""Exercise the actual CI manifest command against an artifact fixture."""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest


def test_ci_manifest_records_actual_artifact_size(tmp_path: Path) -> None:
    node = shutil.which("node")
    if node is None:
        pytest.skip("Node.js is required to exercise the CI manifest command")
    workflow = (Path(__file__).resolve().parents[2] / ".github/workflows/build.yml")
    command = re.search(r"node -e '([^\n]+)'", workflow.read_text(encoding="utf-8"))
    assert command is not None
    artifact = tmp_path / "build/app/outputs/flutter-apk/app-production-release.apk"
    artifact.parent.mkdir(parents=True)
    content = b"release-artifact-fixture"
    artifact.write_bytes(content)
    digest = hashlib.sha256(content).hexdigest().upper()
    env = {
        **os.environ, "APK_SHA256": digest, "CERT_SHA256": "A" * 64,
        "APP_VERSION": "2.0.64+63", "GITHUB_SHA": "b" * 40,
        "BACKEND_URL": "https://example.com",
    }
    subprocess.run(
        [node, "-e", command.group(1)], cwd=tmp_path, env=env,
        check=True, capture_output=True, timeout=15,
    )
    manifest = json.loads((tmp_path / "release-manifest.json").read_text())
    assert manifest["size_bytes"] == len(content)
    assert manifest["apk_sha256"] == digest
    assert manifest["app_version"] == env["APP_VERSION"]
    assert manifest["backend_url"] == env["BACKEND_URL"]
