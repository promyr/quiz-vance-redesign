FROM python:3.14.6-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=8080

WORKDIR /app

COPY requirements.txt .
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        poppler-utils \
        tesseract-ocr \
        tesseract-ocr-por \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --disable-pip-version-check -r requirements.txt \
    && groupadd --gid 10001 quizvance \
    && useradd --uid 10001 --gid quizvance --no-create-home --shell /usr/sbin/nologin quizvance \
    && mkdir -p /data/study_documents \
    && chown -R quizvance:quizvance /data

COPY --chown=quizvance:quizvance alembic.ini .
COPY --chown=quizvance:quizvance alembic ./alembic
COPY --chown=quizvance:quizvance app ./app
COPY --chown=quizvance:quizvance releases ./releases
COPY --chown=quizvance:quizvance scripts/publish_telegram_release_link.py ./scripts/

USER 10001

CMD ["sh", "-c", "alembic upgrade head && exec gunicorn app.main:app --bind 0.0.0.0:${PORT:-8080} --workers ${WEB_CONCURRENCY:-1} --worker-class uvicorn.workers.UvicornWorker --timeout 120"]
