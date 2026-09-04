from __future__ import annotations

import hashlib
import re
import unicodedata
from collections.abc import Iterable
from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class AnalysisWindow:
    text: str
    page_numbers: tuple[int, ...]


def _plain(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", str(value or ""))
    ascii_text = "".join(
        character
        for character in normalized
        if not unicodedata.combining(character)
    )
    return re.sub(r"\s+", " ", ascii_text).strip().lower()


def _clean_topics(value: Any) -> list[str]:
    raw_items: list[Any]
    if isinstance(value, list):
        raw_items = value
    elif isinstance(value, str):
        raw_items = re.split(r"[;\n]", value)
    else:
        raw_items = []

    output: list[str] = []
    seen: set[str] = set()
    for item in raw_items:
        if isinstance(item, dict):
            item = item.get("titulo") or item.get("descricao") or item.get("nome")
        cleaned = re.sub(r"\s+", " ", str(item or "")).strip(" .;:-")
        key = _plain(cleaned)
        if cleaned and key not in seen:
            seen.add(key)
            output.append(cleaned[:500])
    return output[:300]


def consolidate_analysis(
    partials: Iterable[tuple[dict[str, Any], tuple[int, ...]]],
) -> list[dict[str, Any]]:
    by_subject: dict[str, dict[str, Any]] = {}
    order: list[str] = []
    for partial, source_pages in partials:
        disciplines = partial.get("disciplinas")
        if not isinstance(disciplines, list):
            continue
        allowed_pages = {int(page) for page in source_pages}
        for raw_subject in disciplines:
            if not isinstance(raw_subject, dict):
                continue
            name = re.sub(
                r"\s+",
                " ",
                str(
                    raw_subject.get("nome")
                    or raw_subject.get("disciplina")
                    or raw_subject.get("materia")
                    or ""
                ),
            ).strip(" .;:-")
            topics = _clean_topics(
                raw_subject.get("topicos")
                or raw_subject.get("assuntos")
                or raw_subject.get("conteudo_programatico")
            )
            if not name or not topics:
                continue
            key = _plain(name)
            if key not in by_subject:
                order.append(key)
                by_subject[key] = {
                    "nome": name[:200],
                    "topicos": [],
                    "evidencias": [],
                }
            target = by_subject[key]
            existing_topics = {_plain(item) for item in target["topicos"]}
            for topic in topics:
                topic_key = _plain(topic)
                if topic_key not in existing_topics:
                    existing_topics.add(topic_key)
                    target["topicos"].append(topic)

            raw_evidence = raw_subject.get("evidencias")
            if not isinstance(raw_evidence, list):
                raw_evidence = []
                evidence_text = str(raw_subject.get("evidencia") or "").strip()
                if evidence_text:
                    raw_evidence = [
                        {"pagina": page, "trecho": evidence_text}
                        for page in sorted(allowed_pages)[:1]
                    ]
            existing_evidence = {
                (int(item["pagina"]), _plain(item["trecho"]))
                for item in target["evidencias"]
            }
            for evidence in raw_evidence:
                if not isinstance(evidence, dict):
                    continue
                try:
                    page_number = int(
                        evidence.get("pagina") or evidence.get("page") or 0
                    )
                except (TypeError, ValueError):
                    continue
                snippet = re.sub(
                    r"\s+",
                    " ",
                    str(
                        evidence.get("trecho")
                        or evidence.get("evidencia")
                        or evidence.get("text")
                        or ""
                    ),
                ).strip()
                evidence_key = (page_number, _plain(snippet))
                if (
                    page_number in allowed_pages
                    and snippet
                    and evidence_key not in existing_evidence
                ):
                    existing_evidence.add(evidence_key)
                    target["evidencias"].append(
                        {"pagina": page_number, "trecho": snippet[:500]}
                    )
    return [by_subject[key] for key in order if by_subject[key]["topicos"]]


def analysis_window_hash(*, cargo_title: str, window: AnalysisWindow) -> str:
    digest = hashlib.sha256()
    digest.update(_plain(cargo_title).encode("utf-8"))
    digest.update(b"\0")
    digest.update(",".join(str(page) for page in window.page_numbers).encode("ascii"))
    digest.update(b"\0")
    digest.update(window.text.encode("utf-8"))
    return digest.hexdigest()


def split_analysis_window(
    window: AnalysisWindow,
    *,
    minimum_chars: int,
) -> tuple[AnalysisWindow, ...]:
    text = window.text
    if len(text) <= minimum_chars:
        return ()
    midpoint = len(text) // 2
    lower_bound = max(1, midpoint - min(1_000, midpoint))
    upper_bound = min(len(text) - 1, midpoint + 1_000)
    split_at = text.rfind("\n", lower_bound, upper_bound)
    if split_at <= 0:
        split_at = midpoint
    left = text[:split_at].strip()
    right = text[split_at:].strip()
    if not left or not right:
        return ()
    return (
        AnalysisWindow(text=left, page_numbers=window.page_numbers),
        AnalysisWindow(text=right, page_numbers=window.page_numbers),
    )
