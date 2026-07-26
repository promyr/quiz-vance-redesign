from __future__ import annotations

DEFAULT_MODELS = {
    "gemini": "gemini-3.5-flash",
    "openai": "gpt-4o-mini",
    "groq": "llama-3.3-70b-versatile",
}

RETIRED_MODELS = {
    "gemini-2.0-flash",
}


def normalize_provider(provider: str | None) -> str:
    normalized = str(provider or "gemini").strip().lower()
    if normalized == "gpt":
        return "openai"
    if normalized in DEFAULT_MODELS:
        return normalized
    return "gemini"


def default_model_for_provider(provider: str | None) -> str:
    return DEFAULT_MODELS.get(normalize_provider(provider), DEFAULT_MODELS["gemini"])


def model_matches_provider(provider: str | None, model: str | None) -> bool:
    normalized_provider = normalize_provider(provider)
    normalized_model = str(model or "").strip().lower()
    if not normalized_model:
        return False

    if normalized_provider == "gemini":
        return "gemini" in normalized_model
    if normalized_provider == "openai":
        return normalized_model.startswith(("gpt", "o1", "o3", "o4"))
    if normalized_provider == "groq":
        return any(
            token in normalized_model
            for token in ("llama", "mixtral", "gemma", "deepseek", "qwen")
        )
    return False


def resolve_model_for_provider(
    provider: str | None,
    *,
    stored_model: str | None,
    stored_provider: str | None = None,
    requested_model: str | None = None,
) -> str:
    normalized_provider = normalize_provider(provider)
    requested = str(requested_model or "").strip()
    if model_matches_provider(normalized_provider, requested):
        return requested

    current = str(stored_model or "").strip()
    if (
        current.lower() not in RETIRED_MODELS
        and normalize_provider(stored_provider) == normalized_provider
        and model_matches_provider(normalized_provider, current)
    ):
        return current

    return default_model_for_provider(normalized_provider)
