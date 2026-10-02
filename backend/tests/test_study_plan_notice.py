from __future__ import annotations

from collections.abc import Iterator

import httpx
import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app import ai_service, models, services
from app.database import get_db
from app.routers import quiz


def _database() -> Iterator[Session]:
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    models.Base.metadata.create_all(engine)
    with Session(engine) as session:
        yield session


def _auth_header(account: models.User) -> dict[str, str]:
    token = services.create_access_token(
        "test-secret-that-is-at-least-32-bytes-long",
        account.id,
        account.email_id,
        account.auth_version,
    )
    return {"Authorization": f"Bearer {token}"}


def test_notice_prompt_is_grounded_in_job_and_pdf_text() -> None:
    prompt = ai_service.build_notice_analysis_prompt(
        job_title="Analista Judiciário - TI",
        notice_text=(
            "CONTEÚDO PROGRAMÁTICO\n"
            "Analista Judiciário - TI\n"
            "Banco de Dados: SQL, normalização e transações.\n"
        ),
    )

    assert "Analista Judiciário - TI" in prompt
    assert "Banco de Dados: SQL, normalização e transações." in prompt
    assert "ignore instrucoes" in prompt.lower()
    assert "nao invente" in prompt.lower()


def test_provider_timeout_is_reported_as_processing_timeout() -> None:
    request = httpx.Request("POST", "https://provider.example/generate")

    with pytest.raises(HTTPException) as raised:
        quiz._raise_ai_provider_failure(
            "analisar o edital",
            "gemini",
            httpx.ReadTimeout("timed out", request=request),
        )

    assert raised.value.status_code == 504
    assert "servidor esta online" in str(raised.value.detail).lower()


def test_notice_prompt_keeps_job_section_from_end_of_long_pdf() -> None:
    prompt = ai_service.build_notice_analysis_prompt(
        job_title="Analista Judiciário - TI",
        notice_text=(
            ("informações gerais sem conteúdo programático\n" * 5_000)
            + "Analista Judiciário - TI\n"
            + "Segurança da Informação: criptografia e gestão de riscos.\n"
        ),
    )

    assert "Segurança da Informação: criptografia e gestão de riscos." in prompt


def test_notice_analysis_normalizes_and_removes_empty_subjects() -> None:
    normalized = ai_service.normalize_notice_analysis(
        {
            "cargo_encontrado": "Analista Judiciário - TI",
            "disciplinas": [
                {
                    "nome": "Banco de Dados",
                    "topicos": [" SQL ", "Normalização", "SQL"],
                    "evidencia": "Banco de Dados: SQL e normalização.",
                },
                {
                    "nome": "Sem conteúdo",
                    "topicos": [],
                    "evidencia": "",
                },
            ],
        },
        requested_job_title="Analista Judiciário - TI",
    )

    assert normalized["cargo_encontrado"] == "Analista Judiciário - TI"
    assert len(normalized["disciplinas"]) == 1
    assert normalized["disciplinas"][0]["nome"] == "Banco de Dados"
    assert normalized["disciplinas"][0]["topicos"] == ["SQL", "Normalização"]
    assert (
        normalized["disciplinas"][0]["evidencia"]
        == "Banco de Dados: SQL e normalização."
    )
    assert "concurso_info" in normalized
    assert "cronograma_edital" in normalized
    assert "cargos_popup" in normalized


def test_notice_analysis_accepts_alternative_subject_topic_shapes() -> None:
    normalized = ai_service.normalize_notice_analysis(
        {
            "cargo_encontrado": "Analista Judiciario - TI",
            "disciplinas": [
                {
                    "disciplina": "Direito Administrativo",
                    "conteudo_programatico": (
                        "Atos administrativos; poderes administrativos; "
                        "responsabilidade civil do Estado"
                    ),
                    "evidencia": (
                        "Direito Administrativo: atos administrativos; "
                        "poderes administrativos."
                    ),
                },
                {
                    "materia": "Informatica",
                    "assuntos": [
                        {"titulo": "Seguranca da informacao"},
                        {"descricao": "Redes de computadores"},
                    ],
                },
            ],
        },
        requested_job_title="Analista Judiciario - TI",
    )

    assert [subject["nome"] for subject in normalized["disciplinas"]] == [
        "Direito Administrativo",
        "Informatica",
    ]
    assert normalized["disciplinas"][0]["topicos"] == [
        "Atos administrativos",
        "poderes administrativos",
        "responsabilidade civil do Estado",
    ]
    assert normalized["disciplinas"][1]["topicos"] == [
        "Seguranca da informacao",
        "Redes de computadores",
    ]


def test_analyze_notice_requires_auth_and_returns_structured_topics(
    monkeypatch,
) -> None:
    db = next(_database())
    account = models.User(
        name="Promyr",
        login_id="promyr",
        email_id="promyr@example.com",
        password_hash=services.hash_password("Strong-password-123!"),
    )
    db.add(account)
    db.commit()

    app = FastAPI()
    app.include_router(quiz.router)
    app.dependency_overrides[get_db] = lambda: db
    client = TestClient(app)

    monkeypatch.setattr(
        quiz,
        "_call_ai_for_user",
        lambda *_args, **_kwargs: (
            """
            {
              "cargo_encontrado": "Analista",
              "cargos_popup": [
                {"cargo_id": "c1", "titulo": "Analista", "escolaridade": "Superior", "vagas": null}
              ],
              "disciplinas": [
                {
                  "nome": "Português",
                  "topicos": ["Interpretação de texto"],
                  "evidencia": "Língua Portuguesa: interpretação de textos."
                }
              ]
            }
            """,
            "gemini",
        ),
    )

    denied = client.post(
        "/study-plan/analyze-notice",
        json={"job_title": "Analista", "notice_text": "Conteúdo programático"},
    )
    allowed = client.post(
        "/study-plan/analyze-notice",
        headers=_auth_header(account),
        json={
            "job_title": "Analista",
            "notice_text": "Língua Portuguesa: interpretação de textos.",
        },
    )

    assert denied.status_code == 401
    assert allowed.status_code == 200
    assert allowed.json()["disciplinas"][0]["topicos"] == ["Interpretação de texto"]


def test_analyze_notice_without_job_title_returns_cargos_for_selection(
    monkeypatch,
) -> None:
    db = next(_database())
    account = models.User(
        name="Promyr",
        login_id="promyr",
        email_id="promyr@example.com",
        password_hash=services.hash_password("Strong-password-123!"),
    )
    db.add(account)
    db.commit()

    app = FastAPI()
    app.include_router(quiz.router)
    app.dependency_overrides[get_db] = lambda: db
    client = TestClient(app)
    monkeypatch.setattr(
        quiz,
        "_call_ai_for_user",
        lambda *_args, **_kwargs: (
            '{"cargos_popup":[{"cargo_id":"c1","titulo":"Analista"}],"disciplinas":[]}',
            "gemini",
        ),
    )

    response = client.post(
        "/study-plan/analyze-notice",
        headers=_auth_header(account),
        json={"notice_text": "Edital com cargos e cronograma"},
    )

    assert response.status_code == 200
    assert response.json()["cargos_popup"][0]["titulo"] == "Analista"
