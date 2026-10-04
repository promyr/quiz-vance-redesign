from __future__ import annotations

import httpx
import pytest

from app import document_worker
from app.admin_ai import classify_provider_error
from app.document_processing import DocumentProcessingError, build_analysis_windows


def test_early_cargo_reference_does_not_hide_distant_syllabus() -> None:
    pages = [
        {"page_number": number, "text": "Informacoes administrativas."}
        for number in range(1, 14)
    ]
    pages[0]["text"] = "Quadro de vagas: Analista de Sistemas"
    pages[9]["text"] = "CONTEUDO PROGRAMATICO\nConhecimentos gerais: Portugues."
    pages[10]["text"] = "Raciocinio logico: proposicoes e conjuntos."

    windows = build_analysis_windows(pages, cargo_title="Analista de Sistemas")

    evidence_pages = {page for window in windows for page in window.page_numbers}
    assert {10, 11}.issubset(evidence_pages)
    assert "Raciocinio logico" in "\n".join(window.text for window in windows)
    assert all(len(window.text) <= 8_000 for window in windows)


def test_segment_prompt_separates_other_cargos_from_explicitly_shared_content() -> None:
    prompt = document_worker.build_segment_analysis_prompt(
        cargo_title="Analista de Sistemas",
        text="[PAGINA 10]\nCONTEUDO PROGRAMATICO",
        page_numbers=(10,),
        segment_index=1,
        segment_total=1,
    )

    assert "outros cargos" in prompt
    assert "conteudo comum" in prompt
    assert "explicitamente" in prompt
    assert "pagina da lista permitida" in prompt


def test_syllabus_continuation_is_not_cut_off_after_two_pages() -> None:
    pages = [
        {"page_number": number, "text": "Continuação do anexo: tópicos da prova."}
        for number in range(1, 18)
    ]
    pages[0]["text"] = "Vagas: Analista de Sistemas"
    pages[8]["text"] = "CONTEUDO PROGRAMATICO: Analista de Sistemas"
    pages[15]["text"] = "Banco de dados: normalizacao e transacoes."
    windows = build_analysis_windows(pages, cargo_title="Analista de Sistemas")
    assert 16 in {page for window in windows for page in window.page_numbers}
    assert "normalizacao" in "\n".join(window.text for window in windows)


@pytest.mark.parametrize(
    ("error", "code"),
    [
        (httpx.ReadTimeout("read timed out"), "timeout"),
        (httpx.ConnectTimeout("connect timed out"), "timeout"),
        (httpx.WriteTimeout("write timed out"), "timeout"),
        (httpx.PoolTimeout("pool timed out"), "timeout"),
        (httpx.ConnectError("connection failed"), "provider_unavailable"),
        (httpx.ReadError("connection dropped"), "provider_unavailable"),
        (httpx.RemoteProtocolError("server disconnected"), "provider_unavailable"),
    ],
)
def test_httpx_transient_failures_remain_retryable(monkeypatch, error, code) -> None:
    monkeypatch.setattr(
        document_worker, "build_ai_candidates", lambda *_a, **_k: [object()]
    )

    def failing_call(*_args, **_kwargs):
        raise error

    monkeypatch.setattr(document_worker, "call_ai_with_fallback", failing_call)
    analyzer = document_worker.build_default_analyzer(object(), object())

    assert classify_provider_error(error) == code
    with pytest.raises(DocumentProcessingError) as raised:
        analyzer("[PAGINA 10]\nTexto", (10,), 1, 1)
    assert raised.value.retryable is True
    assert raised.value.code == code


@pytest.mark.parametrize(
    "error",
    [httpx.InvalidURL("invalid URL"), httpx.LocalProtocolError("invalid request")],
)
def test_invalid_client_requests_are_not_retried(error) -> None:
    assert classify_provider_error(error) == "provider_error"


def test_prompt_revision_does_not_reuse_old_analysis_checkpoint(monkeypatch):
    from app import document_processing as processing

    window = processing.build_analysis_windows(
        [{"page_number": 1, "text": "CONTEUDO PROGRAMATICO: Portugues"}],
        cargo_title="Analista",
    )[0]
    current_key = processing._analysis_window_hash(cargo_title="Analista", window=window)
    monkeypatch.setattr(processing, "ANALYSIS_CHECKPOINT_VERSION", 1)
    previous_key = processing._analysis_window_hash(cargo_title="Analista", window=window)
    assert current_key != previous_key


def test_manual_cargo_allowed_when_cargos_already_present() -> None:
    from unittest.mock import MagicMock

    from app.routers import documents

    mock_doc = MagicMock(
        id=10,
        user_id=42,
        purpose="study_plan",
        status="awaiting_selection",
        cargos=[{"id": "cargo_1", "title": "Cargo Inicial", "page_number": 1}],
        selected_cargo_title=None,
        selected_cargo_page=None,
    )
    payload = documents.SelectCargoIn(cargo_id="manual", cargo_title="Cargo Customizado")
    title = payload.cargo_title.strip()
    has_pages = True
    cargo = None
    if cargo is None and payload.cargo_id == "manual" and payload.cargo_title and has_pages and title:
        cargo = {"id": "manual", "title": title, "page_number": None}
        current_cargos = [c for c in list(mock_doc.cargos or []) if str(c.get("id") or "") != "manual"]
        current_cargos.append(cargo)
        mock_doc.cargos = current_cargos

    assert cargo is not None
    assert cargo["title"] == "Cargo Customizado"
    assert any(c["id"] == "manual" for c in mock_doc.cargos)


def test_regular_user_consumes_admin_master_keys(monkeypatch) -> None:
    from unittest.mock import MagicMock

    from app import ai_gateway
    from app.admin_ai import AiCredentialCandidate

    mock_user = MagicMock(id=99, role="user")
    mock_db = MagicMock()
    mock_db.query().filter().first.return_value = None

    expected_candidate = AiCredentialCandidate(
        provider="gemini",
        model="gemini-2.5-flash",
        api_key="master-api-key",
        key_id=1,
        source="server_pool",
    )
    monkeypatch.setattr(
        ai_gateway,
        "select_master_key_candidates",
        lambda _db, preferred_provider=None: [expected_candidate],
    )
    monkeypatch.setattr(ai_gateway.os, "getenv", lambda *args: "")

    candidates = ai_gateway.build_ai_candidates(mock_user, mock_db)
    assert len(candidates) == 1
    assert candidates[0].source == "server_pool"
    assert candidates[0].api_key == "master-api-key"
