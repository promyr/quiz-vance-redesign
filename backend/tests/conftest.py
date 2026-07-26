from __future__ import annotations

import os
import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

os.environ.setdefault(
    "APP_BACKEND_SECRET", "test-secret-that-is-at-least-32-bytes-long"
)
os.environ.setdefault("ALLOW_INSECURE_BOOT", "1")
os.environ.setdefault("DATABASE_URL", "sqlite+pysqlite:///./backend/.pytest.sqlite3")
