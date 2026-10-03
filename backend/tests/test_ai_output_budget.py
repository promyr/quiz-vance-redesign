from __future__ import annotations

from typing import ClassVar

from app import ai_service


class _FakeResponse:
    def __init__(self, payload: dict):
        self._payload = payload

    def raise_for_status(self) -> None:
        return None

    def json(self) -> dict:
        return self._payload


class _RecordingClient:
    requests: ClassVar[list[dict]] = []

    def __init__(self, *args, **kwargs):
        del args, kwargs

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return None

    def post(self, url, *, json, headers):
        del headers
        self.requests.append({"url": url, "json": json})
        if "generativelanguage" in url:
            return _FakeResponse(
                {"candidates": [{"content": {"parts": [{"text": "ok"}]}}]}
            )
        return _FakeResponse({"choices": [{"message": {"content": "ok"}}]})


def test_provider_payloads_honor_the_per_call_output_budget(monkeypatch) -> None:
    _RecordingClient.requests = []
    monkeypatch.setattr(ai_service.httpx, "Client", _RecordingClient)

    gemini = ai_service.call_ai(
        "gemini",
        "gemini-key",
        "gemini-3.8-flash",
        "system",
        "prompt",
        max_output_tokens=1500,
    )
    groq = ai_service.call_ai(
        "groq",
        "groq-key",
        "llama-3.3-70b-versatile",
        "system",
        "prompt",
        max_output_tokens=1500,
    )

    assert gemini == "ok"
    assert groq == "ok"
    assert _RecordingClient.requests[0]["json"]["generationConfig"][
        "maxOutputTokens"
    ] == 1500
    gemini_payload = _RecordingClient.requests[0]["json"]
    assert "temperature" not in gemini_payload["generationConfig"]
    assert (
        gemini_payload["generationConfig"]["responseMimeType"]
        == "application/json"
    )
    assert gemini_payload["generationConfig"]["thinkingConfig"] == {
        "thinkingLevel": "minimal"
    }
    assert gemini_payload["systemInstruction"] == {
        "parts": [{"text": "system"}]
    }
    assert gemini_payload["contents"] == [
        {"role": "user", "parts": [{"text": "prompt"}]}
    ]
    assert _RecordingClient.requests[1]["json"]["max_tokens"] == 1500
