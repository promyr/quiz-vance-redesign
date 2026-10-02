from __future__ import annotations

import httpx

from app import ai_service


def test_groq_retries_a_supported_model_after_model_not_found(monkeypatch) -> None:
    attempted: list[str] = []

    def fake_call(
        _api_key: str,
        model: str,
        _system: str,
        _user: str,
        base_url: str,
        *,
        max_output_tokens: int | None = None,
    ) -> str:
        del base_url, max_output_tokens
        attempted.append(model)
        if len(attempted) == 1:
            request = httpx.Request("POST", "https://api.groq.com/openai/v1/chat/completions")
            response = httpx.Response(404, request=request)
            raise httpx.HTTPStatusError("model not found", request=request, response=response)
        return "ok"

    monkeypatch.setattr(ai_service, "_call_chat_completion_api", fake_call)

    result = ai_service._call_groq(
        "gsk-test",
        "llama-3.3-70b-versatile",
        "system",
        "user",
    )

    assert result == "ok"
    assert attempted == ["llama-3.3-70b-versatile", "openai/gpt-oss-20b"]


def test_groq_does_not_retry_authentication_errors(monkeypatch) -> None:
    attempted: list[str] = []

    def fake_call(
        _api_key: str,
        model: str,
        _system: str,
        _user: str,
        base_url: str,
        *,
        max_output_tokens: int | None = None,
    ) -> str:
        del base_url, max_output_tokens
        attempted.append(model)
        request = httpx.Request("POST", "https://api.groq.com/openai/v1/chat/completions")
        response = httpx.Response(401, request=request)
        raise httpx.HTTPStatusError("unauthorized", request=request, response=response)

    monkeypatch.setattr(ai_service, "_call_chat_completion_api", fake_call)

    try:
        ai_service._call_groq("bad-key", "llama-3.3-70b-versatile", "system", "user")
    except httpx.HTTPStatusError as exc:
        assert exc.response.status_code == 401
    else:
        raise AssertionError("expected authentication error")

    assert attempted == ["llama-3.3-70b-versatile"]
