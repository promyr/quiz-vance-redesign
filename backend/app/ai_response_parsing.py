"""Defensive parsing helpers for structured AI responses."""

from __future__ import annotations

import json
import re
from typing import Any


def _strip_markdown(text: str) -> str:
    return text.strip().replace("```json", "").replace("```", "").strip()


def extract_json_list(text: str) -> list[dict[str, Any]]:
    normalized = _strip_markdown(text)
    try:
        parsed = json.loads(normalized)
        if isinstance(parsed, list):
            return [item for item in parsed if isinstance(item, dict)]
        if isinstance(parsed, dict):
            return [parsed]
    except (TypeError, ValueError, json.JSONDecodeError):
        pass

    match = re.search(r"\[[\s\S]*\]", normalized)
    if match:
        try:
            parsed = json.loads(match.group(0))
            if isinstance(parsed, list):
                return [item for item in parsed if isinstance(item, dict)]
        except (TypeError, ValueError, json.JSONDecodeError):
            pass

    return []


def extract_json_object(text: str) -> dict[str, Any]:
    normalized = _strip_markdown(text)
    try:
        parsed = json.loads(normalized)
        if isinstance(parsed, dict):
            return parsed
    except (TypeError, ValueError, json.JSONDecodeError):
        pass

    match = re.search(r"\{[\s\S]*\}", normalized)
    if match:
        try:
            parsed = json.loads(match.group(0))
            return parsed if isinstance(parsed, dict) else {}
        except (TypeError, ValueError, json.JSONDecodeError):
            pass

    return {}
