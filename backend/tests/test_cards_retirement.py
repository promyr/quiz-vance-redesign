from fastapi.testclient import TestClient

from app.ai_service import build_library_prompt
from app.main import app


def test_active_card_endpoints_are_retired_but_old_offline_reviews_can_settle():
    # Exercise routing instead of relying on FastAPI's eager/lazy router internals.
    with TestClient(app) as client:
        assert client.get("/flashcards").status_code == 404
        assert client.post("/flashcards/create", json={}).status_code == 404
        assert client.post("/flashcards/sync", json={}).status_code == 404
        assert client.post("/flashcards/review", json={}).status_code == 422
    assert "/flashcards/review" not in app.openapi()["paths"]


def test_library_prompt_no_longer_requests_cards():
    prompt = build_library_prompt("Matemática", "Médio", "Frações e operações")
    assert "flashcard" not in prompt.lower()
    assert "questoes" in prompt
