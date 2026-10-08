from app.material_sanitization import (
    sanitize_library_package_response,
    sanitize_reference_material,
)


def test_library_prompt_keeps_short_source_as_only_scope():
    from app.ai_service import build_library_prompt

    prompt = build_library_prompt(
        "qa-matematica.pdf", "intermediario", "Dois mais dois resulta em quatro."
    )
    assert "UNICA autoridade" in prompt
    assert "Dois mais dois resulta em quatro." in prompt
    assert "nivel altera profundidade" in prompt


def test_library_route_rejects_supplied_material_without_readable_content(monkeypatch):
    import pytest
    from fastapi import HTTPException

    from app.routers import quiz

    monkeypatch.setattr(quiz, "_require_user", lambda *args: object())
    for content in ("", "ISBN 978-85-0000-000-0"):
        with pytest.raises(HTTPException) as error:
            quiz.generate_library_package(
                quiz.LibraryPackageIn(topic="vazio.pdf", context=content),
                authorization="test",
                db=None,
            )
        assert error.value.status_code == 422


def test_repeated_didactic_sentence_retains_one_occurrence():
    material = (
        "CONTEUDO PROGRAMATICO\nAdicao\n" + "Dois mais dois resulta em quatro.\n" * 12
    )
    cleaned = sanitize_reference_material(material)
    assert cleaned.count("Dois mais dois resulta em quatro.") == 1


def test_short_source_does_not_allow_unrelated_library_topics():
    package = sanitize_library_package_response(
        {
            "titulo": "Matemática Intermediária",
            "resumo_curto": "Álgebra, cálculo e probabilidade.",
            "topicos_principais": [
                "Cálculo diferencial",
                "Probabilidade",
                "Adição resulta em quatro",
            ],
        },
        topic="qa-matematica.pdf",
        context="Dois mais dois resulta em quatro.",
    )
    assert package["topicos_principais"] == ["Adição resulta em quatro"]
    assert "probabilidade" not in package["resumo_curto"].lower()


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
