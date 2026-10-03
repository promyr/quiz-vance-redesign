from __future__ import annotations

import os
import sqlite3
import sys
from datetime import date, datetime
from pathlib import Path


def _adapt_sqlite_date(value: date) -> str:
    return value.isoformat()


def _adapt_sqlite_datetime(value: datetime) -> str:
    return value.isoformat(" ")


sqlite3.register_adapter(date, _adapt_sqlite_date)
sqlite3.register_adapter(datetime, _adapt_sqlite_datetime)

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

os.environ.setdefault(
    "APP_BACKEND_SECRET", "test-secret-that-is-at-least-32-bytes-long"
)
os.environ.setdefault("ALLOW_INSECURE_BOOT", "1")
os.environ.setdefault("ENVIRONMENT", "test")
_test_sqlite_path = (BACKEND_ROOT / ".pytest.sqlite3").as_posix()
os.environ.setdefault("DATABASE_URL", f"sqlite+pysqlite:///{_test_sqlite_path}")

