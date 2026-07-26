import sys

sys.path.insert(0, "/app")

from app import models
from app.database import SessionLocal


def main() -> None:
    db = SessionLocal()
    try:
        user = db.query(models.User).filter(models.User.login_id == "admin").first()
        print(f"ADMIN_EXISTS={bool(user)};ADMIN_ID={user.id if user else ''}")
    finally:
        db.close()


if __name__ == "__main__":
    main()
