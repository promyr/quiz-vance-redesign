"""Keep the premises of structured questions with their answer alternatives."""

from __future__ import annotations

import re
import unicodedata
from typing import Any


def _items(value: Any) -> list[dict[str, str]]:
    if not isinstance(value, list):
        return []
    result = []
    for index, item in enumerate(value):
        if isinstance(item, dict):
            label = str(item.get("id") or item.get("label") or index + 1).strip()
            text = str(item.get("texto") or item.get("text") or "").strip()
        else:
            label, text = str(index + 1), str(item or "").strip()
        if not text:
            return []
        result.append({"id": label, "text": text})
    return result


def _has_inline_columns(text: str) -> bool:
    labels = re.findall(r"(?:^|\s)\(?([A-Z]+|\d+)\s*[.)—:]\s*\S", text)
    numeric = {label for label in labels if label.isdigit()}
    roman = {label for label in labels if re.fullmatch(r"[IVXLCDM]+", label)}
    letters = {label for label in labels if re.fullmatch(r"[A-Z]", label)}
    # Four dates or four numbered assertions are not two association columns.
    if len(numeric) >= 2 and (len(roman) >= 2 or len(letters) >= 2):
        return True
    columns = re.split(r"\bcoluna\s+(?:[IVX]+|[AB12])\s*[:—]?", text, flags=re.IGNORECASE)
    if len(columns) < 3:
        return False
    return all(
        len(re.findall(r"(?:^|\s)\(?[A-Z\d]+\s*[.)—:]\s*\S", column)) >= 2
        for column in columns[1:3]
    )


def question_structure(question: dict[str, Any], text: str) -> tuple[str, dict] | None:
    """Return a self-contained statement, or reject missing association premises.

    Inline legacy questions remain accepted when their numbered premises are
    already present. Structured columns are flattened for older/mobile clients
    and also retained as metadata for consumers that support richer rendering.
    """
    association = question.get("association") or {}
    if not isinstance(association, dict):
        association = {}
    left = _items(question.get("coluna_esquerda") or association.get("left"))
    right = _items(question.get("coluna_direita") or association.get("right"))
    propositions = _items(question.get("proposicoes") or question.get("propositions"))
    kind = str(question.get("tipo") or question.get("type") or "").lower()
    plain = "".join(c for c in unicodedata.normalize("NFD", text.lower()) if not unicodedata.combining(c))
    is_association = kind in {"associacao", "association", "matching"} or bool(
        re.search(r"\b(?:associe|relacione)\b.*\b(?:colunas|itens|proposicoes)\b", plain)
    ) or bool(left or right or association)
    metadata: dict[str, Any] = {}
    if is_association:
        if len(left) >= 2 and len(right) >= 2:
            metadata["association"] = {"left": left, "right": right}
            for title, items in (("Coluna I", left), ("Coluna II", right)):
                rendered = "\n".join(f"{item['id']} — {item['text']}" for item in items)
                block = f"{title}\n{rendered}"
                # Mentioning a concept does not preserve its association label.
                # Only the complete labeled column proves it is already shown.
                if block not in text:
                    text += f"\n\n{block}"
        elif not _has_inline_columns(text):
            return None
    if propositions:
        metadata["propositions"] = propositions
        block = "Proposições\n" + "\n".join(
            f"{item['id']} — {item['text']}" for item in propositions
        )
        if block not in text:
            text += f"\n\n{block}"
    return text, metadata


def structured_question_rules() -> str:
    return (
        "Questões de associação e proposições:\n"
        "- Quando a base contiver exercícios de associe/relacione, inclua esse formato na geração.\n"
        "- Para associação use tipo=associacao, coluna_esquerda e coluna_direita: listas de objetos com id e texto.\n"
        "- Preserve todas as proposições e ambas as colunas necessárias para resolver, sem mostrar apenas as sequências de respostas.\n"
        "- Para análise de afirmações, use proposicoes: lista de objetos com id (I, II, III) e texto integral.\n"
        "- As alternativas continuam sendo sequências de associação ou combinações de proposições, com uma única correta.\n"
        "- Não invente proposições ausentes de um exercício extraído. Se estiver incompleto, descarte-o e gere outro exercício autônomo.\n"
    )


def complete_cached_questions(questions: list[dict]) -> list[dict]:
    result = []
    for question in questions:
        complete = question_structure(question, str(question.get("text") or ""))
        if complete is not None:
            text, metadata = complete
            result.append({**question, "text": text, **metadata})
    return result
