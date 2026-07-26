"""
AI content generation engine for Quiz Vance.

Used by quiz, simulado, open quiz, study plan and library routes.
Each call is stateless: receives provider/api_key/prompt and returns text.
"""

from __future__ import annotations

import json
import logging
import re
import unicodedata
from collections import Counter
from typing import Any

import httpx

logger = logging.getLogger(__name__)

_TIMEOUT = httpx.Timeout(45.0, connect=10.0)


# Parsing helpers


def _strip_markdown(text: str) -> str:
    return text.strip().replace("```json", "").replace("```", "").strip()


def extract_json_list(text: str) -> list[dict]:
    text = _strip_markdown(text)
    try:
        parsed = json.loads(text)
        if isinstance(parsed, list):
            return [item for item in parsed if isinstance(item, dict)]
        if isinstance(parsed, dict):
            return [parsed]
    except Exception:
        pass

    match = re.search(r"\[[\s\S]*\]", text)
    if match:
        try:
            parsed = json.loads(match.group(0))
            if isinstance(parsed, list):
                return [item for item in parsed if isinstance(item, dict)]
        except Exception:
            pass

    return []


def extract_json_object(text: str) -> dict:
    text = _strip_markdown(text)
    try:
        parsed = json.loads(text)
        if isinstance(parsed, dict):
            return parsed
    except Exception:
        pass

    match = re.search(r"\{[\s\S]*\}", text)
    if match:
        try:
            return json.loads(match.group(0))
        except Exception:
            pass

    return {}


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


def _call_gemini(api_key: str, model: str, system: str, user: str) -> str:
    model_id = model or "gemini-3.5-flash"
    # A chave é enviada via header x-goog-api-key, nunca como query param,
    # para evitar que ela seja registrada em logs de proxy, CDN e servidor.
    url = (
        "https://generativelanguage.googleapis.com/v1beta/models/"
        f"{model_id}:generateContent"
    )
    headers = {
        "x-goog-api-key": api_key,
        "Content-Type": "application/json",
    }
    contents: list[dict[str, Any]] = []
    if system:
        contents.append({"role": "user", "parts": [{"text": system}]})
        contents.append({"role": "model", "parts": [{"text": "Entendido."}]})
    contents.append({"role": "user", "parts": [{"text": user}]})
    payload = {
        "contents": contents,
        "generationConfig": {
            "temperature": 0.7,
            "maxOutputTokens": 8192,
        },
    }

    with httpx.Client(timeout=_TIMEOUT) as client:
        response = client.post(url, json=payload, headers=headers)
        response.raise_for_status()

    data = response.json()
    candidates = data.get("candidates") or []
    if not candidates:
        raise ValueError("Gemini retornou 0 candidatos")
    parts = candidates[0].get("content", {}).get("parts") or []
    return "".join(part.get("text", "") for part in parts)


def _call_openai(
    api_key: str,
    model: str,
    system: str,
    user: str,
    base_url: str = "https://api.openai.com/v1",
) -> str:
    model_id = model or "gpt-4o-mini"
    messages: list[dict[str, str]] = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": user})

    payload = {
        "model": model_id,
        "messages": messages,
        "temperature": 0.7,
        "max_tokens": 8192,
    }
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }

    with httpx.Client(timeout=_TIMEOUT) as client:
        response = client.post(
            f"{base_url}/chat/completions", json=payload, headers=headers
        )
        response.raise_for_status()

    data = response.json()
    choices = data.get("choices") or []
    if not choices:
        raise ValueError("OpenAI retornou 0 choices")
    return choices[0].get("message", {}).get("content", "")


def _call_groq(api_key: str, model: str, system: str, user: str) -> str:
    model_id = model or "llama-3.3-70b-versatile"
    return _call_openai(
        api_key, model_id, system, user, base_url="https://api.groq.com/openai/v1"
    )


def call_ai(
    provider: str,
    api_key: str,
    model: str,
    system_prompt: str,
    user_prompt: str,
) -> str:
    """
    Single entrypoint for providers. Raises on failure.
    """
    normalized_provider = (provider or "gemini").lower().strip()
    if not api_key:
        raise ValueError(f"api_key vazia para provider={normalized_provider}")

    if normalized_provider == "gemini":
        return _call_gemini(api_key, model, system_prompt, user_prompt)
    if normalized_provider in ("openai", "gpt"):
        return _call_openai(api_key, model, system_prompt, user_prompt)
    if normalized_provider == "groq":
        return _call_groq(api_key, model, system_prompt, user_prompt)
    raise ValueError(f"Provider desconhecido: {normalized_provider}")


# Prompt builders

_NIVEL: dict[str, tuple[str, str]] = {
    "iniciante": (
        "INICIANTE",
        "Perguntas diretas sobre conceitos basicos. Alternativas erradas contem erros claros.",
    ),
    "facil": (
        "FACIL",
        "Perguntas sobre fundamentos. Alternativas erradas trocam um detalhe especifico.",
    ),
    "intermediario": (
        "INTERMEDIARIO",
        "Exige entender relacoes entre conceitos ou aplicar regras a situacoes.",
    ),
    "dificil": (
        "DIFICIL",
        "Situacoes praticas que exigem analise. Alternativas erradas sao parcialmente corretas.",
    ),
    "mestre": (
        "MESTRE",
        "Casos complexos com multiplas interpretacoes plausiveis. Dominio profundo.",
    ),
    "medio": (
        "INTERMEDIARIO",
        "Exige entender relacoes entre conceitos ou aplicar regras a situacoes.",
    ),
    "avancado": (
        "DIFICIL",
        "Situacoes praticas que exigem analise. Alternativas erradas sao parcialmente corretas.",
    ),
    "easy": (
        "FACIL",
        "Perguntas sobre fundamentos. Alternativas erradas trocam um detalhe especifico.",
    ),
}

_SYSTEM_QUIZ = (
    "Voce e o motor de questoes do Quiz Vance, app brasileiro de estudo.\n"
    "Seu trabalho e gerar questoes objetivas de multipla escolha sobre CONTEUDO DIDATICO.\n"
    "REGRA ABSOLUTA: cada questao deve ser respondivel por qualquer estudante do tema "
    "sem acesso a nenhum documento especifico. Se a questao so faz sentido porque ha "
    "um texto, livro ou arquivo disponivel, ela e invalida.\n"
    "Pergunte sobre: conceitos, definicoes, mecanismos, processos, fenomenos, relacoes "
    "causais, aplicacoes praticas, comparacoes entre conceitos, excecoes e exemplos.\n"
    "NUNCA pergunte sobre: autoria, editora, edicao, ISBN, estrutura do livro, capitulos, "
    "paginas, sumario, prefacio, agradecimentos, ficha catalografica ou qualquer dado "
    "que identifique a fonte — esses dados nao existem para o aluno.\n"
    "Responda SOMENTE com um array JSON. Comece com [ e termine com ].\n"
    "Nunca inclua markdown, explicacoes fora do JSON ou campos extras."
)

_SYSTEM_OPEN = (
    "Voce e um avaliador pedagogico do Quiz Vance.\n"
    "Gere questoes dissertativas profundas, relevantes e pedagogicamente uteis.\n"
    "Antes de responder, identifique silenciosamente o nucleo conceitual do tema e descarte detalhes editoriais.\n"
    "REGRA ABSOLUTA: a questao deve ser respondivel sem acesso a nenhum documento especifico; use a base apenas para extrair conhecimento do dominio.\n"
    "Responda SOMENTE com um objeto JSON valido."
)

_SYSTEM_GRADE = (
    "Voce e um avaliador pedagogico criterioso do Quiz Vance.\n"
    "Avalie a resposta do aluno com base na pergunta e na resposta esperada.\n"
    "Responda SOMENTE com um objeto JSON valido."
)

_SYSTEM_PLAN = (
    "Voce e um tutor especializado do Quiz Vance.\n"
    "Crie um plano de estudos personalizado, progressivo e acionavel.\n"
    "Antes de responder, pense silenciosamente em prioridades, lacunas, distribuicao de carga e variacao entre semanas.\n"
    "Responda SOMENTE com um objeto JSON valido."
)

_SYSTEM_LIBRARY = (
    "Voce e um criador de material didatico do Quiz Vance.\n"
    "Gere um pacote de estudo completo sobre o tema.\n"
    "Responda SOMENTE com um objeto JSON valido."
)


def _avoid_items_block(
    title: str,
    items: list[str] | None,
    *,
    limit: int,
    max_chars: int,
) -> str:
    if not items:
        return ""
    rendered = "\n".join(
        f"- {item[:max_chars]}" for item in items[:limit] if item.strip()
    )
    if not rendered:
        return ""
    return f"\n{title}:\n{rendered}\n"


def _json_only_rules_block(expected_shape: str) -> str:
    return (
        "Regras de saida:\n"
        "- Retorne somente JSON valido.\n"
        "- Nao use markdown, comentarios, cercas de codigo ou texto introdutorio.\n"
        "- Se faltar base para algum item, devolva menos itens em vez de inventar.\n"
        f"- Estrutura esperada: {expected_shape}\n"
    )


def _grounding_rules_block() -> str:
    return (
        "Regras de aderencia ao dominio:\n"
        "- Pense primeiro no nucleo conceitual do tema antes de escrever.\n"
        "- Se houver contexto, use-o para extrair conceitos, definicoes, processos, relacoes e exemplos legitimos.\n"
        "- Ignore completamente ruído editorial: autoria, editora, ISBN, DOI, sumario, paginas, capitulos, copyright, referencias, links e creditos.\n"
        "- Nunca mencione o arquivo, o texto, o PDF, a apostila, o autor ou o documento na saida final.\n"
        "- O aluno final nao tem acesso ao material-fonte; a saida precisa fazer sentido sozinha.\n"
    )


def build_quiz_prompt(
    topic: str,
    difficulty: str,
    quantity: int,
    context: str | None = None,
    avoid: list[str] | None = None,
) -> str:
    nivel_label, nivel_instrucao = _NIVEL.get(
        (difficulty or "intermediario").lower().strip(),
        _NIVEL["intermediario"],
    )
    ctx_block = _material_context_block(context, limit=4000)
    avoid_block = _avoid_items_block(
        "Perguntas ja usadas - nao repita nem faca variacoes muito proximas",
        avoid,
        limit=30,
        max_chars=150,
    )

    return f"""Tarefa: gere {quantity} questoes de multipla escolha sobre \"{topic}\".

{ctx_block}{avoid_block}
Dificuldade alvo: {nivel_label}
Guia de dificuldade: {nivel_instrucao}

{_grounding_rules_block()}
Regras pedagogicas:
- Produza exatamente {quantity} questoes.
- Cubra subtemas diferentes e evite perguntas redundantes.
- Priorize conceitos, mecanismos, comparacoes, aplicacoes, excecoes e cenarios curtos.
- Cada enunciado deve ser autonomo e entendivel fora do material-fonte.
- Crie 4 alternativas plausiveis, com apenas 1 correta.
- Varie a posicao da alternativa correta entre as questoes.
- A explicacao deve justificar a correta e diferenciar o erro principal das demais.
- Subtema curto, especifico e util para analytics.
- Se o contexto estiver fraco, gere perguntas mais fundamentais em vez de inventar detalhes.

Teste de validade:
- Remova mentalmente o documento-fonte.
- Se a pergunta deixar de fazer sentido, descarte e gere outra.

{_json_only_rules_block("array de objetos com pergunta, subtema, opcoes, correta_index e explicacao")}
[
  {{
    "pergunta": "...",
    "subtema": "...",
    "opcoes": ["A", "B", "C", "D"],
    "correta_index": 0,
    "explicacao": "..."
  }}
]"""


def build_simulado_prompt(
    topic: str | None,
    difficulty: str,
    quantity: int,
    context: str | None = None,
    avoid: list[str] | None = None,
) -> str:
    nivel_label, nivel_instrucao = _NIVEL.get(
        (difficulty or "intermediario").lower().strip(),
        _NIVEL["intermediario"],
    )
    tema_block = (
        f"Tema/Area: {topic}"
        if topic
        else (
            "Tema: concursos publicos gerais (direito, portugues, raciocinio logico, informatica, administracao publica)"
        )
    )
    ctx_block = _material_context_block(context, limit=4000)
    avoid_block = _avoid_items_block(
        "Questoes ja usadas - nao repita nem faca variacoes muito proximas",
        avoid,
        limit=30,
        max_chars=150,
    )

    return f"""Tarefa: gere {quantity} questoes de simulado em estilo concurso publico.

{tema_block}
{ctx_block}{avoid_block}
Dificuldade alvo: {nivel_label}
Guia de dificuldade: {nivel_instrucao}

{_grounding_rules_block()}
Regras de simulado:
- Produza exatamente {quantity} questoes.
- Estilo inspirado em bancas como FGV, FCC, Vunesp e CESPE, sem copiar nenhuma banca real.
- Misture cobranca conceitual, aplicacao, excecao, interpretacao e caso pratico.
- 4 alternativas plausiveis e apenas 1 correta.
- Enunciados objetivos, sem depender do documento original.
- Se o tema for amplo, distribua as questoes entre subareas relevantes.
- Evite duas questoes consecutivas sobre o mesmo microtema.
- A explicacao deve reforcar o raciocinio de prova e nao apenas repetir a resposta.

Teste de validade:
- A questao precisa continuar valida para qualquer candidato do tema mesmo sem ver o material-fonte.

{_json_only_rules_block("array de objetos com pergunta, subtema, opcoes, correta_index e explicacao")}
[
  {{
    "pergunta": "...",
    "subtema": "...",
    "opcoes": ["A", "B", "C", "D"],
    "correta_index": 0,
    "explicacao": "..."
  }}
]"""


def build_open_question_prompt(
    tema: str,
    dificuldade: str,
    conteudo: str | None = None,
    avoid: list[str] | None = None,
) -> str:
    ctx_block = _material_context_block(conteudo, limit=3000)
    avoid_block = _avoid_items_block(
        "Perguntas dissertativas ja geradas - nao repita nem faca variacoes muito proximas",
        avoid,
        limit=15,
        max_chars=150,
    )
    return f"""Tarefa: crie 1 questao dissertativa sobre \"{tema}\".

Dificuldade alvo: {dificuldade}
{ctx_block}{avoid_block}
{_grounding_rules_block()}
Regras pedagogicas:
- A questao deve exigir explicacao, comparacao, justificativa, analise ou articulacao de conceitos.
- Evite perguntas que possam ser respondidas com uma palavra ou definicao rasa.
- O campo \"contexto\" deve orientar a resposta esperada sem entregar a solucao.
- \"resposta_esperada\" deve listar os elementos essenciais de uma boa resposta, nao um texto literario fechado.
- Se o contexto fornecido trouxer ruido editorial, descarte esse ruido e foque apenas no nucleo conceitual.

Teste de validade:
- Qualquer estudante do tema deve conseguir responder sem acesso ao documento original.

{_json_only_rules_block("objeto com pergunta, contexto e resposta_esperada")}
{{
  "pergunta": "Enunciado completo da questao",
  "contexto": "Contexto ou orientacao para o aluno",
  "resposta_esperada": "Elementos essenciais que uma boa resposta deve conter"
}}"""


def build_grade_prompt(
    pergunta: str, resposta_esperada: str, resposta_aluno: str
) -> str:
    return f"""Avalie a resposta do aluno com criterio pedagogico e consistencia.

Pergunta: {pergunta}
Resposta esperada: {resposta_esperada}
Resposta do aluno: {resposta_aluno[:2000]}

Regras:
- Compare conteudo, estrutura, clareza e fundamentacao.
- Nao penalize por estilo se o conteudo essencial estiver correto.
- Nao invente erros que nao aparecem na resposta.
- Use feedback acionavel e objetivo.

{_json_only_rules_block("objeto com nota, correto, feedback, pontos_fortes, pontos_melhorar e criterios")}
{{
  "nota": 0-100,
  "correto": true/false,
  "feedback": "Comentario detalhado",
  "pontos_fortes": ["ponto 1", "ponto 2"],
  "pontos_melhorar": ["melhoria 1"],
  "criterios": {{
    "aderencia": 0-100,
    "estrutura": 0-100,
    "clareza": 0-100,
    "fundamentacao": 0-100
  }}
}}"""


def build_study_plan_prompt(
    topics: list[str],
    weeks: int,
    hours_per_week: float,
    level: str,
    goal: str | None,
    avoid_focuses: list[str] | None = None,
) -> str:
    topics_str = ", ".join(topics) if topics else "concurso publico geral"
    goal_block = f"Objetivo: {goal}" if goal else ""
    avoid_block = _avoid_items_block(
        "Enfoques ja usados em planos anteriores - explore angulos diferentes",
        avoid_focuses,
        limit=10,
        max_chars=100,
    )

    return f"""Crie um plano de estudos personalizado, realista e progressivo.

Topicos: {topics_str}
Duracao: {weeks} semanas
Horas por semana: {hours_per_week}h
Nivel atual: {level}
{goal_block}{avoid_block}
{_grounding_rules_block()}
Regras do plano:
- Distribua a carga de forma plausivel ao longo de {weeks} semanas.
- Cada semana deve ter um foco principal claro e tarefas acionaveis.
- Varie entre estudo de base, consolidacao, pratica, revisao e simulacao quando fizer sentido.
- Evite repetir o mesmo foco em todas as semanas.
- Tarefas devem ser concretas, observaveis e orientadas a resultado.
- Prefira nomes de foco especificos, nao titulos vagos como \"estudar mais\" ou \"revisao geral\" em todas as semanas.
- As dicas finais devem ser curtas, praticas e coerentes com o plano.

{_json_only_rules_block("objeto com titulo, descricao, semanas e dicas")}
{{
  "titulo": "Nome do plano",
  "descricao": "Resumo do plano",
  "semanas": [
    {{
      "semana": 1,
      "foco": "Tema principal",
      "topicos": ["topico A", "topico B"],
      "horas_estudo": 10.0,
      "tarefas": ["Tarefa 1", "Tarefa 2"]
    }}
  ],
  "dicas": ["Dica 1", "Dica 2"]
}}"""


def build_library_prompt(
    topic: str,
    level: str,
    context: str | None = None,
    avoid_fronts: list[str] | None = None,
) -> str:
    ctx_block = _material_context_block(context, limit=3500)
    avoid_block = _avoid_items_block(
        "Flashcards ja gerados - nao repita nem faca variacoes muito proximas",
        avoid_fronts,
        limit=20,
        max_chars=120,
    )

    return f"""Tarefa: gere um pacote de estudo sobre \"{topic}\" para nivel {level}.

{ctx_block}{avoid_block}
{_grounding_rules_block()}
Workflow interno silencioso:
- Primeiro identifique os conceitos nucleares realmente sustentados pelo material.
- Depois descarte ruido editorial e trechos bibliograficos.
- So entao monte resumo, topicos, flashcards, questoes e checklist.

Regras do pacote:
- O pacote deve ser util para revisao rapida e estudo orientado.
- Cada topico principal deve representar um conceito central, nao um detalhe editorial.
- Flashcards devem ter frente curta, clara e autoexplicativa.
- O verso do flashcard deve ser objetivo, correto e sem citar o documento.
- Evite pares quase duplicados.
- Questoes devem ter 4 alternativas plausiveis e apenas 1 correta.
- O enunciado deve ser autonomo, sem mencionar texto, capitulo, pagina ou autor.
- O checklist deve ter itens curtos, acionaveis e ligados ao conteudo.
- Se nao houver base segura para algum bloco, devolva lista vazia nesse bloco em vez de inventar.
- Prefira poucos itens muito bons a muitos itens genericos.

{_json_only_rules_block("objeto com titulo, resumo_curto, topicos_principais, sugestoes_flashcards, sugestoes_questoes e checklist_de_estudo")}
{{
  "titulo": "...",
  "resumo_curto": "Resumo curto e objetivo do conteudo",
  "topicos_principais": ["topico 1", "topico 2", "topico 3"],
  "sugestoes_flashcards": [
    {{
      "front": "Pergunta curta",
      "back": "Resposta objetiva"
    }}
  ],
  "sugestoes_questoes": [
    {{
      "pergunta": "...",
      "subtema": "...",
      "opcoes": ["A", "B", "C", "D"],
      "correta_index": 0,
      "explicacao": "..."
    }}
  ],
  "checklist_de_estudo": ["acao 1", "acao 2", "acao 3"]
}}"""


# Quiz response normalization to Flutter format

_OPTION_PREFIX_RE = re.compile(r"^(?:[A-Ea-e][\)\.\:\-]\s*|\d+[\)\.]\s*)")


_METADATA_QUESTION_RE = re.compile(
    r"\b(?:"
    # Autoria e edição
    r"autor(?:es|ia)?|escrev(?:eu|er|ido)|public(?:ou|ado|acao)|"
    r"editor(?:a|ial)?|edicao|isbn|issn|doi|copyright|"
    # Estrutura física do livro
    r"capitulo|cap(?:itulo)?\.?\s*\d|pagina(?:s|cao)?|sumario|indice|"
    r"prefacio|apresentacao|agradecimento|dedicatoria|colofao|"
    r"ficha\s*catalogr|tiragem|grafica|diagramacao|"
    r"capa|contracapa|orelha|sinopse\s*editorial|"
    # Agentes editoriais
    r"quem\s+(?:escreveu|publicou|assinou|organizou|coordenou|fez)|"
    r"assin(?:ou|ado|atura)|organiz(?:ou|ado|ador)|coorden(?:ou|ado|ador)|"
    # Referências implícitas ao documento (frases que dependem do artefato)
    r"segundo\s+o\s+(?:texto|autor|livro|documento|material|trecho|artigo)|"
    r"de\s+acordo\s+com\s+o\s+(?:texto|autor|livro|documento|material)|"
    r"conforme\s+(?:apresentado|descrito|indicado|o\s+texto|o\s+autor)|"
    r"no\s+(?:texto|documento|livro|material|trecho|artigo)\s+(?:acima|abaixo|fornecido|dado|lido)|"
    r"o\s+(?:texto|trecho|documento|material|livro)\s+(?:afirma|indica|apresenta|descreve|diz|mostra)|"
    r"com\s+base\s+no\s+(?:texto|documento|material|trecho|livro)|"
    r"leia\s+o\s+(?:texto|trecho|excerto)"
    r")\b",
    re.IGNORECASE,
)


def filter_metadata_questions(questions: list[dict]) -> list[dict]:
    """Remove questoes que perguntem sobre metadados, autoria ou estrutura editorial."""
    filtered = []
    for q in questions:
        pergunta = str(q.get("pergunta") or q.get("text") or "").lower()
        opcoes_text = " ".join(
            str(o) for o in (q.get("opcoes") or q.get("options") or [])
        ).lower()
        combined = f"{pergunta} {opcoes_text}"
        if _METADATA_QUESTION_RE.search(combined):
            logger.info("Filtered metadata question: %s", pergunta[:80])
            continue
        filtered.append(q)
    return filtered


def normalize_quiz_questions(raw_questions: list[dict]) -> list[dict[str, Any]]:
    """
    Convert internal quiz format (pergunta/opcoes/correta_index) into the
    format expected by Flutter Question.fromJson.
    """
    import uuid

    result: list[dict[str, Any]] = []
    for i, question in enumerate(raw_questions):
        if not isinstance(question, dict):
            continue

        pergunta = str(question.get("pergunta") or "").strip()
        if not pergunta:
            continue

        opcoes_raw = question.get("opcoes") or []
        if not isinstance(opcoes_raw, list) or len(opcoes_raw) < 2:
            continue

        try:
            correta_idx = int(str(question.get("correta_index", 0)).strip())
        except Exception:
            correta_idx = 0
        correta_idx = max(0, min(correta_idx, len(opcoes_raw) - 1))

        options: list[dict[str, Any]] = []
        correct_id: str | None = None

        for j, option_text in enumerate(opcoes_raw[:4]):
            clean = _OPTION_PREFIX_RE.sub("", str(option_text or "")).strip()
            option_id = f"opt_{i}_{j}"
            is_correct = j == correta_idx
            if is_correct:
                correct_id = option_id
            options.append(
                {
                    "id": option_id,
                    "text": clean,
                    "isCorrect": is_correct,
                }
            )

        if correct_id is None and options:
            correct_id = options[0]["id"]
            options[0]["isCorrect"] = True

        result.append(
            {
                "id": str(uuid.uuid4()),
                "text": pergunta,
                "topic": str(question.get("subtema") or "").strip() or None,
                "options": options,
                "correctOptionId": correct_id,
                "explanation": str(question.get("explicacao") or "").strip() or None,
            }
        )

    return result
