"""Android release metadata and APK download endpoints."""

from __future__ import annotations

import os
import re
from datetime import datetime
from pathlib import Path

from fastapi import APIRouter, HTTPException, Query, Request
from fastapi.responses import FileResponse

from .. import schemas, telegram_bot

router = APIRouter(tags=["releases"])
_BACKEND_ROOT = Path(__file__).resolve().parents[2]


def _android_latest_version() -> str:
    return str(
        os.getenv("ANDROID_APP_LATEST_VERSION") or os.getenv("APP_LATEST_VERSION") or ""
    ).strip()


def _android_minimum_supported_version() -> str:
    return str(
        os.getenv("ANDROID_APP_MIN_SUPPORTED_VERSION")
        or os.getenv("APP_MIN_SUPPORTED_VERSION")
        or ""
    ).strip()


def _android_download_url() -> str:
    return str(telegram_bot.download_url() or "").strip()


def _android_release_file_path() -> str:
    return str(_BACKEND_ROOT / "releases" / "android" / "quiz-vance.apk")


def _android_versioned_release_file_path(version: str) -> str:
    version_clean = str(version or "").strip()
    if not re.fullmatch(r"[0-9A-Za-z._+-]+", version_clean):
        return ""
    filename = f"quiz-vance-{version_clean}.apk"
    return str(_BACKEND_ROOT / "releases" / "android" / filename)


def _android_backend_download_url(request: Request | None = None) -> str:
    if not os.path.isfile(_android_release_file_path()):
        return ""
    base_url = ""
    if request is not None:
        try:
            base_url = str(request.base_url or "").strip().rstrip("/")
        except (AttributeError, TypeError, ValueError):
            base_url = ""
    public_base = str(os.getenv("BACKEND_PUBLIC_URL") or "").strip().rstrip("/")
    root = public_base or base_url
    if not root:
        return ""
    return f"{root}/app/download/android/latest.apk"


def _android_release_notes() -> str:
    return str(
        os.getenv("ANDROID_APP_RELEASE_NOTES") or os.getenv("APP_RELEASE_NOTES") or ""
    ).strip()


def _android_published_at() -> datetime | None:
    raw = str(
        os.getenv("ANDROID_APP_PUBLISHED_AT") or os.getenv("APP_PUBLISHED_AT") or ""
    ).strip()
    if not raw:
        return None
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None


def _version_parts(value: str) -> list[int]:
    parts = [int(chunk) for chunk in re.findall(r"\d+", str(value or ""))]
    return parts or [0]


def _is_version_newer(left: str, right: str) -> bool:
    left_parts = _version_parts(left)
    right_parts = _version_parts(right)
    size = max(len(left_parts), len(right_parts))
    left_parts.extend([0] * (size - len(left_parts)))
    right_parts.extend([0] * (size - len(right_parts)))
    return left_parts > right_parts


def _app_update_required_detail() -> str:
    minimum = _android_minimum_supported_version()
    latest = _android_latest_version()
    download = _android_download_url() or _android_backend_download_url()
    parts = ["Atualize o aplicativo para continuar."]
    if minimum:
        parts.append(f"Versao minima suportada: {minimum}.")
    if latest:
        parts.append(f"Versao disponivel: {latest}.")
    if download:
        parts.append(f"Baixe em: {download} (ou acesse o Telegram e baixe).")
    return " ".join(parts).strip()


def _require_supported_app_version(app_version: str | None) -> None:
    minimum = _android_minimum_supported_version()
    if not minimum:
        return
    current = str(app_version or "").strip()
    if not current or _is_version_newer(minimum, current):
        raise HTTPException(status_code=426, detail=_app_update_required_detail())


@router.api_route("/app/download/android/latest.apk", methods=["GET", "HEAD"])
def app_download_android_latest():
    apk_path = _android_release_file_path()
    if not os.path.isfile(apk_path):
        raise HTTPException(status_code=404, detail="apk_not_found")
    return FileResponse(
        path=apk_path,
        media_type="application/vnd.android.package-archive",
        filename="quiz-vance.apk",
        headers={"Cache-Control": "no-store"},
    )


@router.api_route("/app/download/android/{version}.apk", methods=["GET", "HEAD"])
def app_download_android_version(version: str):
    apk_path = _android_versioned_release_file_path(version)
    if not apk_path or not os.path.isfile(apk_path):
        raise HTTPException(status_code=404, detail="apk_not_found")
    return FileResponse(
        path=apk_path,
        media_type="application/vnd.android.package-archive",
        filename=f"quiz-vance-{version}.apk",
        headers={"Cache-Control": "no-store"},
    )


@router.get("/app/update", response_model=schemas.AppUpdateInfoOut)
def app_update_info(
    request: Request,
    platform: str = Query(default="android", alias="platform"),
):
    platform_clean = str(platform or "android").strip().lower() or "android"
    if platform_clean != "android":
        return schemas.AppUpdateInfoOut(ok=True, platform=platform_clean)
    download_url = (
        _android_download_url() or _android_backend_download_url(request) or None
    )
    return schemas.AppUpdateInfoOut(
        ok=True,
        platform="android",
        latest_version=_android_latest_version() or None,
        minimum_supported_version=_android_minimum_supported_version() or None,
        download_url=download_url,
        release_notes=_android_release_notes() or None,
        published_at=_android_published_at(),
    )
