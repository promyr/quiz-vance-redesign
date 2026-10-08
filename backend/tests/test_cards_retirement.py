from app.ai_service import build_library_prompt
from app.main import app


def test_active_card_endpoints_are_retired_but_old_offline_reviews_can_settle():
    paths = {route.path for route in app.routes if route.path.startswith("/flashcards")}
    assert paths == {"/flashcards/review"}
    assert "/flashcards/review" not in app.openapi()["paths"]


def test_library_prompt_no_longer_requests_cards():
    prompt = build_library_prompt("Matemática", "Médio", "Frações e operações")
    assert "flashcard" not in prompt.lower()
    assert "questoes" in prompt
