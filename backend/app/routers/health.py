from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import text
from sqlalchemy.orm import Session

from ..database import get_db

router = APIRouter(tags=["health"])


@router.get("/health")
def health() -> dict[str, object]:
    return {"ok": True, "ts": datetime.now(timezone.utc).isoformat()}


@router.get("/health/ready")
def health_ready(db: Session = Depends(get_db)) -> dict[str, object]:
    try:
        db.execute(text("SELECT 1"))
        return {
            "ok": True,
            "db": "up",
            "ts": datetime.now(timezone.utc).isoformat(),
        }
    except Exception as error:
        raise HTTPException(
            status_code=503,
            detail="Banco de dados indisponivel.",
        ) from error
