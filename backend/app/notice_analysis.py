"""Normalization of structured public-notice analysis responses."""

from __future__ import annotations

import re
from typing import Any


def _safe_date_str(value: Any) -> str | None:
    """Valida e normaliza string de data ISO 8601 YYYY-MM-DD. Retorna None se invalida."""
    if not value:
        return None
    s = re.sub(r"\s+", "", str(value)).strip()
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", s):
        return s
    return None


def _clean_notice_topic(value: Any) -> str:
    return re.sub(r"\s+", " ", str(value)).strip(" \t\r\n-•;,.")[:240]


def _split_notice_topics(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, list):
        topics: list[str] = []
        for item in value:
            if isinstance(item, dict):
                item = (
                    item.get("topico")
                    or item.get("titulo")
                    or item.get("nome")
                    or item.get("descricao")
                    or item.get("conteudo")
                )
            topics.extend(_split_notice_topics(item))
        return topics
    text = str(value).strip()
    if not text:
        return []
    # Editais e LLMs variam entre bullets, ponto e virgula e linhas numeradas.
    parts = re.split(r"(?:\n+|;|•|\s+-\s+|(?:^|\s)\d+[.)]\s+)", text)
    if len(parts) == 1:
        parts = re.split(r",(?=\s+[A-ZÁÉÍÓÚÂÊÔÃÕÇ])", text)
    return [_clean_notice_topic(part) for part in parts if _clean_notice_topic(part)]


def normalize_notice_analysis(
    data: dict[str, Any],
    *,
    requested_job_title: str,
) -> dict[str, Any]:
    # ── Concurso Info ────────────────────────────────────────────
    raw_info = data.get("concurso_info") or {}
    if not isinstance(raw_info, dict):
        raw_info = {}
    concurso_info = {
        "orgao": str(raw_info.get("orgao") or "").strip()[:200] or None,
        "banca": str(raw_info.get("banca") or "").strip()[:100] or None,
        "status_edital": str(raw_info.get("status_edital") or "PUBLICADO").strip()[:30],
        "modalidade": str(raw_info.get("modalidade") or "").strip()[:60] or None,
    }

    # ── Cronograma ───────────────────────────────────────────────
    raw_crono = data.get("cronograma_edital") or {}
    if not isinstance(raw_crono, dict):
        raw_crono = {}
    data_prova_str = _safe_date_str(raw_crono.get("data_prova"))
    data_prova_definida_raw = raw_crono.get("data_prova_definida")
    if isinstance(data_prova_definida_raw, bool):
        data_prova_definida = data_prova_definida_raw
    else:
        data_prova_definida = data_prova_str is not None
    cronograma_edital = {
        "data_publicacao": _safe_date_str(raw_crono.get("data_publicacao")),
        "inscricoes_inicio": _safe_date_str(raw_crono.get("inscricoes_inicio")),
        "inscricoes_fim": _safe_date_str(raw_crono.get("inscricoes_fim")),
        "pagamento_limite": _safe_date_str(raw_crono.get("pagamento_limite")),
        "data_prova": data_prova_str,
        "data_prova_definida": data_prova_definida,
    }

    # ── Cargos Pop-up ────────────────────────────────────────────
    raw_cargos = data.get("cargos_popup")
    if not isinstance(raw_cargos, list):
        raw_cargos = []
    cargos_popup: list[dict[str, Any]] = []
    seen_cargo_ids: set[str] = set()
    for i, raw_cargo in enumerate(raw_cargos[:50]):
        if not isinstance(raw_cargo, dict):
            continue
        cargo_id = str(raw_cargo.get("cargo_id") or f"c{i + 1}").strip()[:30]
        if cargo_id in seen_cargo_ids:
            cargo_id = f"{cargo_id}_{i}"
        titulo = str(raw_cargo.get("titulo") or "").strip()[:200]
        if not titulo:
            continue
        vagas_raw = raw_cargo.get("vagas")
        vagas: int | None = None
        if isinstance(vagas_raw, (int, float)) and vagas_raw >= 0:
            vagas = int(vagas_raw)
        seen_cargo_ids.add(cargo_id)
        cargos_popup.append(
            {
                "cargo_id": cargo_id,
                "titulo": titulo,
                "escolaridade": str(raw_cargo.get("escolaridade") or "").strip()[:80]
                or None,
                "vagas": vagas,
            }
        )

    # ── Disciplinas ──────────────────────────────────────────────
    found_job = str(data.get("cargo_encontrado") or requested_job_title).strip()
    subjects: list[dict[str, Any]] = []
    seen_subjects: set[str] = set()

    raw_subjects = data.get("disciplinas")
    if not isinstance(raw_subjects, list):
        raw_subjects = []

    for raw_subject in raw_subjects[:20]:
        if not isinstance(raw_subject, dict):
            continue
        name = str(
            raw_subject.get("nome")
            or raw_subject.get("disciplina")
            or raw_subject.get("materia")
            or raw_subject.get("área")
            or raw_subject.get("area")
            or ""
        ).strip()[:160]
        if not name or name.casefold() in seen_subjects:
            continue

        raw_topics = (
            raw_subject.get("topicos")
            or raw_subject.get("assuntos")
            or raw_subject.get("itens")
            or raw_subject.get("conteudos")
            or raw_subject.get("conteudo")
            or raw_subject.get("conteudo_programatico")
            or raw_subject.get("programa")
        )
        topics: list[str] = []
        seen_topics: set[str] = set()
        for raw_topic in _split_notice_topics(raw_topics)[:30]:
            topic = _clean_notice_topic(raw_topic)
            topic_key = topic.casefold()
            if not topic or topic_key in seen_topics:
                continue
            seen_topics.add(topic_key)
            topics.append(topic)
        if not topics:
            continue

        seen_subjects.add(name.casefold())
        evidence = re.sub(
            r"\s+",
            " ",
            str(raw_subject.get("evidencia") or ""),
        ).strip()[:500]

        peso_raw = raw_subject.get("peso")
        peso: int | None = None
        if isinstance(peso_raw, (int, float)) and 1 <= peso_raw <= 10:
            peso = int(peso_raw)

        num_q_raw = raw_subject.get("num_questoes")
        num_questoes: int | None = None
        if isinstance(num_q_raw, (int, float)) and num_q_raw > 0:
            num_questoes = int(num_q_raw)

        subjects.append(
            {
                "nome": name,
                "topicos": topics,
                "evidencia": evidence,
                "peso": peso,
                "num_questoes": num_questoes,
            }
        )

    return {
        "concurso_info": concurso_info,
        "cronograma_edital": cronograma_edital,
        "cargos_popup": cargos_popup,
        "cargo_encontrado": found_job[:160],
        "disciplinas": subjects,
    }

