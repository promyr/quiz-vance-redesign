"""
Testes unitários para o contrato JSON do analisador de editais.

Valida:
- Novo contrato JSON: concurso_info, cronograma_edital, cargos_popup, cargo_encontrado, disciplinas
- Extração de datas ISO 8601 com _safe_date_str
- Fallbacks seguros para campos ausentes
- Corretude da flag data_prova_definida
"""
from __future__ import annotations

from app.ai_service import _safe_date_str, normalize_notice_analysis

# ── _safe_date_str ────────────────────────────────────────────────────────────

class TestSafeDateStr:
    def test_valid_date(self):
        assert _safe_date_str("2026-05-17") == "2026-05-17"

    def test_strips_whitespace(self):
        assert _safe_date_str("  2026-01-01  ") == "2026-01-01"

    def test_invalid_format_dmy(self):
        assert _safe_date_str("17/05/2026") is None

    def test_invalid_format_text(self):
        assert _safe_date_str("a definir") is None

    def test_none_value(self):
        assert _safe_date_str(None) is None

    def test_empty_string(self):
        assert _safe_date_str("") is None


# ── normalize_notice_analysis ─────────────────────────────────────────────────

_FULL_PAYLOAD: dict = {
    "concurso_info": {
        "orgao": "Tribunal de Justiça do Estado X",
        "banca": "FGV",
        "status_edital": "PUBLICADO",
        "modalidade": "Presencial",
    },
    "cronograma_edital": {
        "data_publicacao": "2026-01-15",
        "inscricoes_inicio": "2026-02-01",
        "inscricoes_fim": "2026-02-28",
        "pagamento_limite": "2026-03-02",
        "data_prova": "2026-05-17",
        "data_prova_definida": True,
    },
    "cargos_popup": [
        {
            "cargo_id": "c1",
            "titulo": "Analista Judiciário - Área Administrativa",
            "escolaridade": "Superior",
            "vagas": 10,
        },
        {
            "cargo_id": "c2",
            "titulo": "Técnico Judiciário",
            "escolaridade": "Médio",
            "vagas": 25,
        },
    ],
    "cargo_encontrado": "Analista Judiciário - Área Administrativa",
    "disciplinas": [
        {
            "nome": "Direito Administrativo",
            "topicos": ["Atos administrativos", "Poderes administrativos"],
            "evidencia": "Item 3.1 do edital",
            "peso": 8,
            "num_questoes": 20,
        },
        {
            "nome": "Língua Portuguesa",
            "topicos": ["Gramática", "Interpretação de textos"],
            "evidencia": "Item 3.2 do edital",
            "peso": 5,
            "num_questoes": 10,
        },
    ],
}


class TestNormalizeFullPayload:
    def setup_method(self):
        self.result = normalize_notice_analysis(
            _FULL_PAYLOAD, requested_job_title="Analista"
        )

    def test_keys_present(self):
        keys = {"concurso_info", "cronograma_edital", "cargos_popup", "cargo_encontrado", "disciplinas"}
        assert keys.issubset(self.result.keys())

    # concurso_info
    def test_orgao(self):
        assert self.result["concurso_info"]["orgao"] == "Tribunal de Justiça do Estado X"

    def test_banca(self):
        assert self.result["concurso_info"]["banca"] == "FGV"

    def test_status_edital(self):
        assert self.result["concurso_info"]["status_edital"] == "PUBLICADO"

    # cronograma
    def test_data_prova(self):
        assert self.result["cronograma_edital"]["data_prova"] == "2026-05-17"

    def test_data_prova_definida_true(self):
        assert self.result["cronograma_edital"]["data_prova_definida"] is True

    def test_inscricoes_fim(self):
        assert self.result["cronograma_edital"]["inscricoes_fim"] == "2026-02-28"

    # cargos_popup
    def test_cargos_count(self):
        assert len(self.result["cargos_popup"]) == 2

    def test_cargo_id(self):
        assert self.result["cargos_popup"][0]["cargo_id"] == "c1"

    def test_cargo_vagas(self):
        assert self.result["cargos_popup"][1]["vagas"] == 25

    # cargo e disciplinas
    def test_cargo_encontrado(self):
        assert "Analista" in self.result["cargo_encontrado"]

    def test_disciplinas_count(self):
        assert len(self.result["disciplinas"]) == 2

    def test_disciplina_peso(self):
        d = self.result["disciplinas"][0]
        assert d["peso"] == 8

    def test_disciplina_num_questoes(self):
        d = self.result["disciplinas"][0]
        assert d["num_questoes"] == 20

    def test_disciplina_topicos(self):
        d = self.result["disciplinas"][0]
        assert len(d["topicos"]) == 2


class TestNormalizeMissingFields:
    """Garante fallbacks seguros quando o payload vem incompleto."""

    def test_empty_payload_returns_defaults(self):
        result = normalize_notice_analysis({}, requested_job_title="Cargo Teste")
        assert result["concurso_info"]["status_edital"] == "PUBLICADO"
        assert result["cronograma_edital"]["data_prova"] is None
        assert result["cronograma_edital"]["data_prova_definida"] is False
        assert result["cargos_popup"] == []
        assert result["disciplinas"] == []
        assert result["cargo_encontrado"] == "Cargo Teste"

    def test_missing_concurso_info(self):
        payload = dict(_FULL_PAYLOAD)
        payload.pop("concurso_info")
        result = normalize_notice_analysis(payload, requested_job_title="X")
        assert result["concurso_info"]["orgao"] is None

    def test_invalid_date_becomes_none(self):
        payload = {**_FULL_PAYLOAD, "cronograma_edital": {"data_prova": "A definir", "data_prova_definida": False}}
        result = normalize_notice_analysis(payload, requested_job_title="X")
        assert result["cronograma_edital"]["data_prova"] is None
        assert result["cronograma_edital"]["data_prova_definida"] is False

    def test_data_prova_definida_inferred_from_date_presence(self):
        payload = {**_FULL_PAYLOAD, "cronograma_edital": {"data_prova": "2027-03-10"}}
        result = normalize_notice_analysis(payload, requested_job_title="X")
        # data_prova_definida não foi enviada, mas data_prova é válida → deve inferir True
        assert result["cronograma_edital"]["data_prova_definida"] is True

    def test_cargo_without_titulo_skipped(self):
        payload = {
            **_FULL_PAYLOAD,
            "cargos_popup": [{"cargo_id": "c1", "titulo": "", "escolaridade": "Superior", "vagas": 5}],
        }
        result = normalize_notice_analysis(payload, requested_job_title="X")
        assert len(result["cargos_popup"]) == 0

    def test_duplicate_cargo_id_deduped(self):
        payload = {
            **_FULL_PAYLOAD,
            "cargos_popup": [
                {"cargo_id": "c1", "titulo": "Cargo A", "escolaridade": "Superior", "vagas": 1},
                {"cargo_id": "c1", "titulo": "Cargo B", "escolaridade": "Médio", "vagas": 2},
            ],
        }
        result = normalize_notice_analysis(payload, requested_job_title="X")
        ids = [c["cargo_id"] for c in result["cargos_popup"]]
        assert len(set(ids)) == len(ids), "Cargo IDs devem ser únicos após normalização"

    def test_peso_out_of_range_becomes_none(self):
        payload = {**_FULL_PAYLOAD, "disciplinas": [
            {"nome": "Matemática", "topicos": ["Aritmética"], "evidencia": "", "peso": 15, "num_questoes": 5}
        ]}
        result = normalize_notice_analysis(payload, requested_job_title="X")
        assert result["disciplinas"][0]["peso"] is None

    def test_disciplina_with_no_topicos_skipped(self):
        payload = {**_FULL_PAYLOAD, "disciplinas": [
            {"nome": "Estatística", "topicos": [], "evidencia": "", "peso": 3}
        ]}
        result = normalize_notice_analysis(payload, requested_job_title="X")
        assert len(result["disciplinas"]) == 0
