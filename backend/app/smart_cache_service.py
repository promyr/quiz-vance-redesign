"""
smart_cache_service.py — Semantic Question Pool & Fast AI Response Caching.

Reduz custos de tokens ao reutilizar perguntas de alta qualidade já geradas
para tópicos idênticos.
"""

from __future__ import annotations

import hashlib
import logging
import re
from typing import Any

from sqlalchemy.orm import Session

logger = logging.getLogger(__name__)


def compute_semantic_key(topic: str, difficulty: str = "intermediario", context: str | None = None) -> str:
    """Gera uma chave determinística para agrupamento semântico."""
    norm_topic = re.sub(r"\s+", " ", topic.lower().strip())
    norm_diff = difficulty.lower().strip()
    ctx_hash = ""
    if context:
        ctx_hash = hashlib.sha256(context.strip().encode("utf-8")).hexdigest()[:12]

    raw = f"{norm_topic}|{norm_diff}|{ctx_hash}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:24]


class SmartQuestionCache:
    """Gerencia pool de questões em cache para acelerar geração e cortar custos."""

    @staticmethod
    def get_cached_questions(
        db: Session,
        user_id: int,
        topic: str,
        difficulty: str = "intermediario",
        quantity: int = 10,
        context: str | None = None,
    ) -> list[dict[str, Any]]:
        """Pool compartilhado de questões completas desativado enquanto não houver persistência de alternativas.
        
        QuizSeenQuestion armazena apenas fingerprints e texto para deduplicação (avoid list),
        não contendo alternativas (options) nem justificativas. Retorna [] para garantir geração
        completa via IA com todas as alternativas.
        """
        return []

    @staticmethod
    def get_candidate_questions(
        db: Session,
        topic: str,
        difficulty: str = "intermediario",
        limit: int = 20,
    ) -> list[dict[str, Any]]:
        """Retorna [] para delegar a geração integral à IA com todas as alternativas e explicações.
        
        Evita servir objetos parciais sem opções que quebrariam a interface do aplicativo.
        """
        return []

    @staticmethod
    def store_questions(
        db: Session,
        topic: str,
        difficulty: str,
        questions: list[dict],
    ) -> None:
        """Registra evento de armazenamento no pool compartilhado.

        A persistência real das questões é feita por _store_seen_questions em quiz.py.
        Este método existe para completar a interface e logar o evento sem duplicar
        a lógica de upsert.
        """
        logger.debug(
            "smart_cache: %d questoes disponíveis para futura reutilização no tópico '%s'",
            len(questions),
            topic,
        )


smart_question_cache = SmartQuestionCache()
