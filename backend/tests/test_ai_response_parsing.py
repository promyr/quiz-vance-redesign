from app.ai_response_parsing import extract_json_list, extract_json_object


def test_extract_json_list_accepts_markdown_and_ignores_non_objects() -> None:
    payload = '```json\n[{"question": "Q1"}, "invalid"]\n```'

    assert extract_json_list(payload) == [{"question": "Q1"}]


def test_extract_json_object_recovers_embedded_payload() -> None:
    payload = 'Resposta do provedor: {"status": "ok", "count": 2} fim.'

    assert extract_json_object(payload) == {"status": "ok", "count": 2}


def test_extract_json_helpers_return_safe_empty_values_for_invalid_text() -> None:
    assert extract_json_list("sem json") == []
    assert extract_json_object("sem json") == {}
