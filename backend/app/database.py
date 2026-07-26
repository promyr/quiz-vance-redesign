import os

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker

DATABASE_URL = os.getenv(
    "DATABASE_URL", "postgresql+psycopg://postgres:postgres@localhost:5432/quizvance"
)
if DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = "postgresql+psycopg://" + DATABASE_URL[len("postgres://") :]

engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,
    pool_size=int(os.getenv("DB_POOL_SIZE", "5")),
    max_overflow=int(os.getenv("DB_MAX_OVERFLOW", "10")),
    pool_recycle=int(os.getenv("DB_POOL_RECYCLE", "1800")),
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    """Base class para todos os modelos SQLAlchemy 2.x.

    Usa a API nativa do SQLAlchemy 2.x (DeclarativeBase) em vez da função
    legada declarative_base(), que foi depreciada no 2.0 e é incompatível
    com a tipagem Mapped[T] + mapped_column() usada em models.py.
    """


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
