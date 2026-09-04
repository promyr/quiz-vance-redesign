import hashlib
import hmac
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

MP_API_BASE = "https://api.mercadopago.com"


def verify_webhook_signature(
    *,
    data_id: str,
    x_request_id: str,
    x_signature: str,
    secret: str,
) -> bool:
    """Valida ``v1`` usando o template oficial do Mercado Pago."""
    secret_clean = str(secret or "").strip()
    data_id_clean = str(data_id or "").strip().lower()
    request_id_clean = str(x_request_id or "").strip()
    signature_clean = str(x_signature or "").strip()
    if not all((secret_clean, data_id_clean, request_id_clean, signature_clean)):
        return False
    parts: dict[str, str] = {}
    for item in signature_clean.split(","):
        key, separator, value = item.strip().partition("=")
        if separator and key and value:
            parts[key.strip()] = value.strip()
    timestamp = parts.get("ts", "")
    received = parts.get("v1", "")
    if not timestamp or not received:
        return False
    manifest = f"id:{data_id_clean};request-id:{request_id_clean};ts:{timestamp};"
    expected = hmac.new(
        secret_clean.encode("utf-8"),
        manifest.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    return hmac.compare_digest(expected, received)


def _access_token() -> str:
    return str(os.getenv("MP_ACCESS_TOKEN") or "").strip()


def enabled() -> bool:
    return bool(_access_token())


def is_test_token() -> bool:
    token = _access_token().upper()
    return token.startswith("TEST-")


def _http_timeout_s() -> float:
    raw = str(os.getenv("MP_HTTP_TIMEOUT", "8.0")).strip()
    try:
        return max(1.0, float(raw))
    except Exception:
        return 8.0


def _http_retries() -> int:
    raw = str(os.getenv("MP_HTTP_RETRIES", "1")).strip()
    try:
        return max(0, min(3, int(raw)))
    except Exception:
        return 1


def _request(
    method: str, path: str, payload: dict[str, Any] | None = None
) -> tuple[int, dict[str, Any]]:
    token = _access_token()
    if not token:
        return 0, {}
    url = f"{MP_API_BASE}{path}"
    data = None
    if payload is not None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    timeout_s = _http_timeout_s()
    retries = _http_retries()
    attempts = retries + 1
    last_status = 0
    last_payload: dict[str, Any] = {}

    for attempt in range(1, attempts + 1):
        req = urllib.request.Request(
            url, data=data, headers=headers, method=method.upper()
        )
        try:
            # A URL usa exclusivamente o host HTTPS constante do Mercado Pago.
            with urllib.request.urlopen(  # nosec B310
                req, timeout=timeout_s
            ) as resp:
                raw = (resp.read() or b"").decode("utf-8", errors="ignore")
                payload_out = json.loads(raw) if raw else {}
                payload_out = payload_out if isinstance(payload_out, dict) else {}
                return int(resp.status), payload_out
        except urllib.error.HTTPError as e:
            try:
                raw = (e.read() or b"").decode("utf-8", errors="ignore")
                data_err = json.loads(raw) if raw else {}
            except Exception:
                data_err = {}
            data_err = data_err if isinstance(data_err, dict) else {}
            status = int(getattr(e, "code", 0) or 0)
            if "message" not in data_err:
                data_err["message"] = f"HTTP {status}"
            last_status, last_payload = status, data_err
            # Retry apenas para throttling/falhas temporarias de gateway.
            if status in {408, 429, 500, 502, 503, 504} and attempt < attempts:
                time.sleep(0.18 * attempt)
                continue
            return status, data_err
        except Exception as e:
            last_status, last_payload = 0, {"message": str(e)}
            if attempt < attempts:
                time.sleep(0.18 * attempt)
                continue
            return last_status, last_payload

    return last_status, last_payload


def create_checkout_preference(
    *,
    checkout_id: str,
    user_id: int,
    plan_code: str,
    amount_cents: int,
    notification_url: str,
    payer_email: str = "",
    back_url_success: str = "",
    back_url_pending: str = "",
    back_url_failure: str = "",
) -> dict[str, Any]:
    amount = max(0.01, float(amount_cents or 0) / 100.0)
    payload = {
        "items": [
            {
                "title": f"Quiz Vance - {plan_code}",
                "quantity": 1,
                "currency_id": "BRL",
                "unit_price": amount,
            }
        ],
        "external_reference": str(checkout_id),
        "notification_url": str(notification_url or ""),
        "metadata": {
            "checkout_id": str(checkout_id),
            "user_id": int(user_id),
            "plan_code": str(plan_code),
        },
        "auto_return": "approved",
        "binary_mode": False,
    }
    payer_email = str(payer_email or "").strip().lower()
    if payer_email:
        payload["payer"] = {"email": payer_email}

    back_urls = {}
    if str(back_url_success or "").strip():
        back_urls["success"] = str(back_url_success).strip()
    if str(back_url_pending or "").strip():
        back_urls["pending"] = str(back_url_pending).strip()
    if str(back_url_failure or "").strip():
        back_urls["failure"] = str(back_url_failure).strip()
    if back_urls:
        payload["back_urls"] = back_urls

    _status, data = _request("POST", "/checkout/preferences", payload)
    return data or {}


def get_payment(payment_id: str) -> dict[str, Any]:
    if not str(payment_id or "").strip():
        return {}
    _status, data = _request("GET", f"/v1/payments/{payment_id}")
    return data or {}


def search_latest_payment_by_external_reference(
    external_reference: str,
) -> dict[str, Any]:
    ref = str(external_reference or "").strip()
    if not ref:
        return {}
    query = urllib.parse.urlencode(
        {
            "external_reference": ref,
            "sort": "date_created",
            "criteria": "desc",
            "limit": 1,
        }
    )
    _status, data = _request("GET", f"/v1/payments/search?{query}")
    if not isinstance(data, dict):
        return {}
    results = data.get("results")
    if isinstance(results, list) and results:
        first = results[0]
        return first if isinstance(first, dict) else {}
    return {}
