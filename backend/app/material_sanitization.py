"""Sanitization and relevance filters for user-provided study material."""

from __future__ import annotations

import re
import unicodedata
from collections import Counter
from typing import Any

_PAGE_MARKER_RE = re.compile(
    r"^\s*(?:pagina|page)?\s*\d{1,4}(?:\s*(?:/|de)\s*\d{1,4})?\s*$",
    re.IGNORECASE,
)
_TOC_ENTRY_RE = re.compile(r"(?:\.{2,}|…)\s*\d+\s*$", re.IGNORECASE)
_METADATA_PATTERNS = [
    re.compile(r"\bisbn(?:-1[03])?\b", re.IGNORECASE),
    re.compile(r"\bissn\b", re.IGNORECASE),
    re.compile(r"\bdoi\b", re.IGNORECASE),
    re.compile(r"todos os direitos reservados", re.IGNORECASE),
    re.compile(r"all rights reserved", re.IGNORECASE),
    re.compile(r"\bcopyright\b", re.IGNORECASE),
    re.compile(r"ficha catalogr", re.IGNORECASE),
    re.compile(r"cataloga", re.IGNORECASE),
    re.compile(r"\bcip\b", re.IGNORECASE),
    re.compile(r"\beditora\b", re.IGNORECASE),
    re.compile(r"\bpublisher\b", re.IGNORECASE),
    re.compile(r"\bedit(?:ion|ora)?\b", re.IGNORECASE),
    re.compile(r"\bedi(?:cao|caoes|coes)\b", re.IGNORECASE),
    re.compile(r"https?://", re.IGNORECASE),
    re.compile(r"www\.", re.IGNORECASE),
    re.compile(
        r"^\s*(?:sumario|indice|table of contents|contents)\s*$",
        re.IGNORECASE,
    ),
    re.compile(r"refer[eê]ncias?(?: bibliogr[aá]ficas)?", re.IGNORECASE),
    re.compile(r"bibliografia", re.IGNORECASE),
    re.compile(r"fontes consultadas", re.IGNORECASE),
    re.compile(r"cataloga[cç][aã]o na publica[cç][aã]o", re.IGNORECASE),
    re.compile(r"dados internacionais de cataloga[cç][aã]o", re.IGNORECASE),
    re.compile(r"projeto gr[aá]fico", re.IGNORECASE),
    re.compile(r"diagrama[cç][aã]o", re.IGNORECASE),
    re.compile(r"revis[aã]o t[eé]cnica", re.IGNORECASE),
    re.compile(r"revis[aã]o", re.IGNORECASE),
    re.compile(r"coordena[cç][aã]o", re.IGNORECASE),
    re.compile(r"tradu[cç][aã]o", re.IGNORECASE),
    re.compile(r"organiza[cç][aã]o", re.IGNORECASE),
    re.compile(r"organizador(?:a)?", re.IGNORECASE),
    re.compile(r"autor(?:es)?\b", re.IGNORECASE),
    re.compile(r"publicado por", re.IGNORECASE),
    re.compile(r"impresso no brasil", re.IGNORECASE),
]
_FRONT_MATTER_RE = re.compile(
    r"(autor(?:es)?|organiza[cç][aã]o|organizador(?:a)?|coordena[cç][aã]o|revis[aã]o|diagrama[cç][aã]o|projeto gr[aá]fico|tradu[cç][aã]o|publicado por|impresso no brasil|edi[cç][aã]o|cataloga[cç][aã]o na publica[cç][aã]o|dados internacionais de cataloga[cç][aã]o|biblioteca nacional|capa\b)",
    re.IGNORECASE,
)
_REFERENCE_HEADING_RE = re.compile(
    r"^\s*(?:refer[eê]ncias?(?: bibliogr[aá]ficas)?|bibliografia|works cited|references|fontes consultadas)\s*:?\s*$",
    re.IGNORECASE,
)
_REFERENCE_LINE_RE = re.compile(
    r"(dispon[ií]vel em|acesso em|et al\.?|https?://|www\.)",
    re.IGNORECASE,
)
_SURNAME_REFERENCE_RE = re.compile(r"^\s*[A-Z][A-Z\s-]{2,},\s")
_ALL_CAPS_HEADING_RE = re.compile(r"^[A-Z0-9\s\-,:]{4,}$")


def _should_skip_material_line(line: str, repeated_short_lines: dict[str, int]) -> bool:
    normalized = re.sub(r"\s+", " ", line.strip().lower())
    if not normalized:
        return False

    if _PAGE_MARKER_RE.match(line):
        return True
    if _TOC_ENTRY_RE.search(line):
        return True
    if repeated_short_lines.get(normalized, 0) >= 3 and len(normalized) <= 80:
        return True
    if _FRONT_MATTER_RE.search(line):
        return True
    if _looks_like_reference_line(line):
        return True
    if any(pattern.search(line) for pattern in _METADATA_PATTERNS):
        return True

    digits = len(re.findall(r"\d", line))
    letters = len(re.findall(r"[A-Za-z]", line))
    return bool(digits >= 4 and letters <= 6 and len(normalized) <= 60)


def _should_skip_leading_noise(line: str, repeated_short_lines: dict[str, int]) -> bool:
    normalized = re.sub(r"\s+", " ", line.strip().lower())
    if _FRONT_MATTER_RE.search(line) or _looks_like_reference_line(line):
        return True
    if repeated_short_lines.get(normalized, 0) >= 2 and len(normalized) <= 120:
        return True

    words = len(re.findall(r"[A-Za-z0-9]+", line))
    letters = len(re.findall(r"[A-Za-z]", line))
    if _ALL_CAPS_HEADING_RE.match(line) and words <= 8:
        return True
    return bool(words <= 5 and letters <= 40 and "." not in line and ";" not in line)


def _looks_like_reference_line(line: str) -> bool:
    if _REFERENCE_LINE_RE.search(line):
        return True
    if _SURNAME_REFERENCE_RE.match(line):
        return True

    has_year = re.search(r"\b(?:19|20)\d{2}[a-z]?\b", line) is not None
    has_many_separators = re.search(r"[;:]{2,}|,\s*[A-Z]", line) is not None
    return has_year and has_many_separators


def _looks_like_content_line(line: str) -> bool:
    words = len(re.findall(r"[A-Za-z0-9]+", line))
    letters = len(re.findall(r"[A-Za-z]", line))
    return (
        words >= 8
        and letters >= 25
        and not _FRONT_MATTER_RE.search(line)
        and not _looks_like_reference_line(line)
    )


def sanitize_reference_material(text: str | None, limit: int = 4000) -> str:
    raw = (text or "").replace("\r\n", "\n").replace("\r", "\n").replace("\u00a0", " ")
    raw_lines = [re.sub(r"[ \t]+", " ", line).strip() for line in raw.split("\n")]

    repeated_short_lines: dict[str, int] = {}
    for line in raw_lines:
        key = re.sub(r"\s+", " ", line.strip().lower())
        if key and len(key) <= 80:
            repeated_short_lines[key] = repeated_short_lines.get(key, 0) + 1

    cleaned_lines: list[str] = []
    last_was_blank = False
    started_content = False
    skipping_reference_section = False
    for line in raw_lines:
        if not line:
            if skipping_reference_section:
                continue
            if cleaned_lines and not last_was_blank:
                cleaned_lines.append("")
            last_was_blank = True
            continue

        last_was_blank = False
        if _REFERENCE_HEADING_RE.match(line):
            skipping_reference_section = True
            continue
        if skipping_reference_section:
            continue
        if not started_content and _should_skip_leading_noise(
            line, repeated_short_lines
        ):
            continue
        if _should_skip_material_line(line, repeated_short_lines):
            continue
        if _looks_like_content_line(line):
            started_content = True
        cleaned_lines.append(line)

    cleaned = "\n".join(cleaned_lines).strip()
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned)

    return cleaned[:limit].strip()


def _material_context_block(text: str | None, limit: int = 4000) -> str:
    cleaned = sanitize_reference_material(text, limit=limit)
    if not cleaned:
        return ""
    return (
        "\nBase de conhecimento do dominio (use para extrair conceitos, "
        "definicoes, relacoes causais e exemplos — nao mencione esta fonte "
        "nas questoes; o aluno nao tem acesso a ela):\n"
        f"{cleaned}\n"
    )


_LIBRARY_TOKEN_RE = re.compile(r"[A-Za-z0-9]{4,}")
_LIBRARY_STOPWORDS = {
    "para",
    "com",
    "sem",
    "sobre",
    "entre",
    "pelos",
    "pelas",
    "mais",
    "menos",
    "muito",
    "muita",
    "muitos",
    "muitas",
    "como",
    "quando",
    "onde",
    "qual",
    "quais",
    "porque",
    "por",
    "das",
    "dos",
    "uma",
    "umas",
    "uns",
    "esses",
    "essas",
    "esse",
    "essa",
    "este",
    "esta",
    "isto",
    "aquele",
    "aquela",
    "those",
    "with",
    "from",
    "that",
    "this",
    "have",
    "your",
    "their",
    "into",
    "nivel",
    "geral",
    "material",
    "biblioteca",
    "estudo",
    "estudos",
    "conteudo",
    "conteudos",
    "topico",
    "topicos",
    "flashcard",
    "flashcards",
    "questao",
    "questoes",
    "checklist",
    "objetiva",
    "objetivo",
    "resumo",
    "curto",
}
_LIBRARY_METADATA_TOKENS = {
    "isbn",
    "issn",
    "doi",
    "autor",
    "autores",
    "editora",
    "copyright",
    "ficha",
    "catalografica",
    "catalogacao",
    "sumario",
    "indice",
    "pagina",
    "paginas",
    "referencia",
    "referencias",
    "bibliografia",
    "publicado",
    "revisao",
    "organizacao",
    "traducao",
    "capa",
    "rodape",
    "cabecalho",
    "creditos",
    "link",
    "links",
    "disponivel",
    "acesso",
    "site",
    "sites",
}


def _normalize_match_text(text: str) -> str:
    normalized = unicodedata.normalize("NFKD", text or "")
    without_marks = "".join(
        char for char in normalized if not unicodedata.combining(char)
    )
    return without_marks.lower().strip()


def _tokenize_library_relevance(text: str) -> list[str]:
    normalized = _normalize_match_text(text)
    tokens = [match.group(0) for match in _LIBRARY_TOKEN_RE.finditer(normalized)]
    return [
        token
        for token in tokens
        if token not in _LIBRARY_STOPWORDS
        and token not in _LIBRARY_METADATA_TOKENS
        and not token.isdigit()
    ]


def _contains_library_metadata_noise(text: str) -> bool:
    snippet = (text or "").strip()
    if not snippet:
        return False
    if _looks_like_reference_line(snippet):
        return True
    if _REFERENCE_HEADING_RE.match(snippet):
        return True
    if _FRONT_MATTER_RE.search(snippet):
        return True
    if any(pattern.search(snippet) for pattern in _METADATA_PATTERNS):
        return True

    normalized = _normalize_match_text(snippet)
    return any(token in normalized for token in _LIBRARY_METADATA_TOKENS)


def _build_library_relevance_profile(topic: str, context: str | None) -> dict[str, Any]:
    cleaned_context = sanitize_reference_material(context, limit=5000)
    topic_terms = _tokenize_library_relevance(topic)
    context_counts = Counter(_tokenize_library_relevance(cleaned_context))

    anchor_terms: list[str] = []
    for term in topic_terms:
        if term not in anchor_terms:
            anchor_terms.append(term)
    for term, _ in context_counts.most_common(18):
        if term not in anchor_terms:
            anchor_terms.append(term)

    return {
        "strict": len(cleaned_context) >= 180 and len(context_counts) >= 6,
        "topic_terms": set(topic_terms),
        "anchor_terms": set(anchor_terms),
    }


def _is_library_text_relevant(text: str, profile: dict[str, Any]) -> bool:
    snippet = (text or "").strip()
    if not snippet:
        return False
    if _contains_library_metadata_noise(snippet):
        return False

    if not profile["strict"]:
        return True

    tokens = set(_tokenize_library_relevance(snippet))
    if not tokens:
        return False

    topic_overlap = tokens & profile["topic_terms"]
    if topic_overlap:
        return True

    anchor_overlap = tokens & profile["anchor_terms"]
    if len(anchor_overlap) >= 2:
        return True

    return len(anchor_overlap) == 1 and len(snippet) <= 90


def sanitize_library_package_response(
    data: dict[str, Any],
    *,
    topic: str,
    context: str | None,
) -> dict[str, Any]:
    profile = _build_library_relevance_profile(topic, context)

    raw_topics = data.get("topicos_principais") or data.get("pontos_chave") or []
    topicos_principais = [
        str(item).strip()
        for item in raw_topics
        if isinstance(item, str) and _is_library_text_relevant(item, profile)
    ][:8]

    flashcards: list[dict[str, str]] = []
    raw_flashcards = data.get("sugestoes_flashcards") or data.get("flashcards") or []
    seen_fronts_set: set[str] = set()
    for item in raw_flashcards:
        if not isinstance(item, dict):
            continue
        front = str(item.get("front") or item.get("pergunta") or "").strip()
        back = str(item.get("back") or item.get("resposta") or "").strip()
        if not front or not back:
            continue
        if not _is_library_text_relevant(f"{front}\n{back}", profile):
            continue
        # Deduplicate by normalised front text within package
        norm_front = re.sub(r"\s+", " ", front.lower())
        if norm_front and norm_front not in seen_fronts_set:
            seen_fronts_set.add(norm_front)
            flashcards.append({"front": front, "back": back})
        if len(flashcards) >= 16:
            break

    questoes_revisao: list[dict[str, Any]] = []
    raw_questions = data.get("sugestoes_questoes") or data.get("questoes_revisao") or []
    for item in raw_questions:
        if not isinstance(item, dict):
            continue
        pergunta = str(item.get("pergunta") or "").strip()
        if not pergunta:
            continue
        opcoes = item.get("opcoes") if isinstance(item.get("opcoes"), list) else []
        joined_text = "\n".join(
            [
                pergunta,
                str(item.get("subtema") or "").strip(),
                str(item.get("explicacao") or "").strip(),
                *[str(option or "").strip() for option in opcoes[:6]],
            ]
        )
        if not _is_library_text_relevant(joined_text, profile):
            continue
        questoes_revisao.append(item)
        if len(questoes_revisao) >= 10:
            break

    raw_checklist = data.get("checklist_de_estudo") or data.get("dicas_estudo") or []
    checklist_de_estudo = [
        str(item).strip()
        for item in raw_checklist
        if isinstance(item, str)
        and item.strip()
        and not _contains_library_metadata_noise(item)
    ][:10]

    titulo = str(data.get("titulo") or "").strip() or topic
    resumo_curto = str(data.get("resumo_curto") or data.get("resumo") or "").strip()
    if profile["strict"] and not _is_library_text_relevant(
        f"{titulo}\n{resumo_curto}", profile
    ):
        titulo = topic

    return {
        "titulo": titulo,
        "resumo_curto": resumo_curto,
        "resumo": str(data.get("resumo") or resumo_curto).strip(),
        "topicos_principais": topicos_principais,
        "pontos_chave": topicos_principais,
        "sugestoes_flashcards": flashcards,
        "flashcards": flashcards,
        "sugestoes_questoes": questoes_revisao,
        "questoes_revisao": questoes_revisao,
        "checklist_de_estudo": checklist_de_estudo,
        "dicas_estudo": checklist_de_estudo,
        "_strict_relevance": profile["strict"],
    }


# Providers
