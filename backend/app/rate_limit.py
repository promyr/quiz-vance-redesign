"""
In-memory sliding-window rate limit with cleanup and trusted-proxy handling.
"""

from __future__ import annotations

import hashlib
import ipaddress
import os
import threading
import time
from functools import lru_cache

from fastapi import HTTPException, Request
from sqlalchemy import text

from .database import DATABASE_URL, SessionLocal

_RATE_BUCKETS: dict[str, list[float]] = {}
_RATE_LOCK = threading.Lock()

_CLEANUP_INTERVAL_SECONDS = 120
_MAX_BUCKET_ENTRIES = 50_000


def _run_cleanup() -> None:
    while True:
        time.sleep(_CLEANUP_INTERVAL_SECONDS)
        cutoff = time.time() - 3600
        with _RATE_LOCK:
            stale_keys = [
                k for k, ts in _RATE_BUCKETS.items() if not ts or ts[-1] < cutoff
            ]
            for k in stale_keys:
                del _RATE_BUCKETS[k]

            if len(_RATE_BUCKETS) > _MAX_BUCKET_ENTRIES:
                sorted_keys = sorted(
                    _RATE_BUCKETS,
                    key=lambda key: _RATE_BUCKETS[key][-1] if _RATE_BUCKETS[key] else 0,
                )
                evict_count = len(sorted_keys) // 4
                for key in sorted_keys[:evict_count]:
                    del _RATE_BUCKETS[key]


_cleanup_thread = threading.Thread(
    target=_run_cleanup, daemon=True, name="rate-limit-cleanup"
)
_cleanup_thread.start()


def _truthy_env(name: str) -> bool:
    return str(os.getenv(name, "0") or "0").strip().lower() in {
        "1",
        "true",
        "yes",
        "on",
    }


@lru_cache(maxsize=1)
def _trusted_proxy_networks() -> tuple[ipaddress._BaseNetwork, ...]:
    raw = str(os.getenv("TRUSTED_PROXY_IPS", "") or "")
    networks: list[ipaddress._BaseNetwork] = []
    for part in raw.split(","):
        candidate = part.strip()
        if not candidate:
            continue
        try:
            networks.append(ipaddress.ip_network(candidate, strict=False))
        except ValueError:
            continue
    return tuple(networks)


def _is_trusted_proxy(host: str) -> bool:
    candidate = str(host or "").strip()
    if not candidate:
        return False
    try:
        ip_value = ipaddress.ip_address(candidate)
    except ValueError:
        return False
    return any(ip_value in network for network in _trusted_proxy_networks())


def _client_key(request: Request) -> str:
    direct_host = str(
        getattr(getattr(request, "client", None), "host", "") or ""
    ).strip()
    forwarded = str(request.headers.get("X-Forwarded-For") or "").strip()

    if not forwarded or not _truthy_env("TRUST_PROXY_HEADERS"):
        return direct_host or "unknown"

    if not _is_trusted_proxy(direct_host):
        return direct_host or "unknown"

    for candidate in forwarded.split(","):
        value = candidate.strip()
        if not value:
            continue
        try:
            return str(ipaddress.ip_address(value))
        except ValueError:
            continue

    return direct_host or "unknown"


def _scoped_bucket_key(request: Request, max_calls: int, period_seconds: int) -> str:
    raw = (
        f"{_client_key(request)}|{request.url.path}|"
        f"{int(max_calls)}|{int(period_seconds)}"
    )
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _use_database_backend() -> bool:
    configured = str(os.getenv("RATE_LIMIT_BACKEND") or "").strip().lower()
    if configured:
        return configured == "database"
    return DATABASE_URL.startswith("postgresql")


def _database_check(request: Request, max_calls: int, period_seconds: int) -> None:
    bucket_key = _scoped_bucket_key(request, max_calls, period_seconds)
    now_epoch = int(time.time())
    window_start = now_epoch - (now_epoch % int(period_seconds))
    expires_epoch = window_start + int(period_seconds) + 3600
    db = SessionLocal()
    try:
        result = db.execute(
            text(
                """
                INSERT INTO rate_limit_buckets (
                    bucket_key, window_start, request_count, expires_at
                )
                VALUES (:key, :window_start, 1, to_timestamp(:expires_epoch))
                ON CONFLICT (bucket_key)
                DO UPDATE SET
                    window_start = CASE
                        WHEN rate_limit_buckets.window_start < :window_start
                        THEN :window_start
                        ELSE rate_limit_buckets.window_start
                    END,
                    request_count = CASE
                        WHEN rate_limit_buckets.window_start < :window_start
                        THEN 1
                        ELSE rate_limit_buckets.request_count + 1
                    END,
                    expires_at = to_timestamp(:expires_epoch)
                RETURNING request_count
                """
            ),
            {
                "key": bucket_key,
                "window_start": window_start,
                "expires_epoch": expires_epoch,
            },
        )
        count = int(result.scalar_one())
        db.commit()
    except Exception as exc:
        db.rollback()
        raise HTTPException(
            status_code=503,
            detail="Protecao de requisicoes temporariamente indisponivel.",
        ) from exc
    finally:
        db.close()
    if count > max_calls:
        raise HTTPException(
            status_code=429,
            detail="Muitas requisicoes. Aguarde alguns instantes e tente novamente.",
            headers={"Retry-After": str(period_seconds)},
        )


def rate_limit(max_calls: int, period_seconds: int):
    def _check(request: Request) -> None:
        if _use_database_backend():
            _database_check(request, max_calls, period_seconds)
            return
        key = _scoped_bucket_key(request, max_calls, period_seconds)
        now = time.time()
        window_start = now - period_seconds

        with _RATE_LOCK:
            calls = [
                timestamp
                for timestamp in _RATE_BUCKETS.get(key, [])
                if timestamp > window_start
            ]
            if len(calls) >= max_calls:
                raise HTTPException(
                    status_code=429,
                    detail="Muitas requisições. Aguarde alguns instantes e tente novamente.",
                )

            calls.append(now)
            _RATE_BUCKETS[key] = calls

    return _check
