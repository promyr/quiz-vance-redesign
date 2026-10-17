"""Difficulty policy shared by all current question generation modes."""

DIFFICULTY_GUIDES = {
    "mixed": (
        "MISTO (MEDIO E DIFICIL)",
        (
            "Alterne questoes de nivel medio e dificil. Nao gere questoes faceis ou de "
            "mera memorizacao: exija relacoes, aplicacao, comparacao e analise. "
            "Em lotes com pelo menos duas questoes, inclua ambos os niveis."
        ),
    ),
    "hard": (
        "DIFICIL",
        "Situacoes praticas que exigem analise. Alternativas erradas sao parcialmente corretas.",
    ),
}


def normalize_generation_difficulty(value: str | None) -> str:
    """Normalize new requests without reclassifying historical questions."""
    return "hard" if (value or "").strip().lower() in {
        "hard", "dificil", "difícil", "avancado", "avançado", "mestre",
    } else "mixed"
