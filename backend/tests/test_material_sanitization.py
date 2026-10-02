from app.material_sanitization import (
    sanitize_library_package_response,
    sanitize_reference_material,
)


def test_reference_material_removes_page_markers_and_front_matter() -> None:
    material = """
    SUMARIO
    Capitulo 1 ........ 3
    Pagina 4
    Fotossintese converte energia luminosa em energia quimica.
    A clorofila participa da absorcao de luz.
    """

    cleaned = sanitize_reference_material(material)

    assert "Fotossintese" in cleaned
    assert "Pagina 4" not in cleaned
    assert "........ 3" not in cleaned


def test_library_package_keeps_grounded_flashcard_and_drops_noise() -> None:
    payload = {
        "flashcards": [
            {
                "front": "Qual molecula absorve luz na fotossintese?",
                "back": "Clorofila",
            },
            {"front": "Qual e o autor?", "back": "Autor desconhecido"},
        ],
        "summary": "Fotossintese e clorofila.",
    }

    sanitized = sanitize_library_package_response(
        payload,
        topic="Fotossintese",
        context="A clorofila absorve luz durante a fotossintese.",
    )

    assert len(sanitized["flashcards"]) == 1
    assert "clorofila" in sanitized["flashcards"][0]["back"].lower()
