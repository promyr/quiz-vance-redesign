from pathlib import Path

APP_ROOT = Path(__file__).resolve().parents[1] / "app"


def test_ai_service_delegates_parsing_and_notice_normalization() -> None:
    source = (APP_ROOT / "ai_service.py").read_text(encoding="utf-8")

    assert "from .ai_response_parsing import" in source
    assert "from .material_sanitization import" in source
    assert "from .notice_analysis import" in source
    assert len(source.splitlines()) < 950


def test_health_endpoints_are_not_declared_in_main_module() -> None:
    source = (APP_ROOT / "main.py").read_text(encoding="utf-8")

    assert "from .routers import health as health_router" in source
    assert '@app.get("/health")' not in source


def test_release_endpoints_are_isolated_from_app_composition() -> None:
    source = (APP_ROOT / "main.py").read_text(encoding="utf-8")

    assert "from .routers import releases as releases_router" in source
    assert "app.include_router(releases_router.router)" in source
    assert '@app.get("/app/update"' not in source
    assert "from .telegram_scheduler import" in source
    assert len(source.splitlines()) < 1900
