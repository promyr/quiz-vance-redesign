import base64
import hashlib
import hmac
import json
import os
import re
import secrets
import time
import uuid
from datetime import date, datetime, timedelta, timezone

from sqlalchemy import text
from sqlalchemy.orm import Session

from . import models, security

PWD_SCHEME = "pbkdf2_sha256"
PWD_ITERS = 600_000


def _env_int(name: str, default: int) -> int:
    raw = str(os.getenv(name, "") or "").strip()
    if not raw:
        return int(default)
    try:
        return int(raw)
    except ValueError:
        return int(default)


PLAN_DEFINITIONS = {
    "premium_30": {
        "price_cents": _env_int("PREMIUM_30_PRICE_CENTS", 1490),
        "duration_days": 30,
    },
}
PLAN_PRICES_CENTS = {k: int(v["price_cents"]) for k, v in PLAN_DEFINITIONS.items()}


def format_brl_from_cents(value: int) -> str:
    return f"R$ {(int(value) / 100):.2f}".replace(".", ",")


ACCESS_TOKEN_TTL_SECONDS = max(
    900, int(os.getenv("ACCESS_TOKEN_TTL_SECONDS", "900") or 900)
)
REFRESH_TOKEN_TTL_SECONDS = max(
    3600, int(os.getenv("REFRESH_TOKEN_TTL_SECONDS", "2592000") or 2592000)
)
LOGIN_ID_RE = re.compile(r"^[a-z0-9](?:[a-z0-9._-]{1,38}[a-z0-9])?$")


def _b64url_encode(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def _b64url_decode(value: str) -> bytes:
    return base64.urlsafe_b64decode(
        str(value or "") + "=" * (-len(str(value or "")) % 4)
    )


def current_auth_version(user: models.User | None) -> int:
    return max(0, int(getattr(user, "auth_version", 0) or 0))


def token_auth_version(payload: dict | None) -> int:
    return max(0, int((payload or {}).get("ver") or 0))


def token_matches_user(payload: dict | None, user: models.User | None) -> bool:
    return token_auth_version(payload) == current_auth_version(user)


def _create_token(
    app_secret: str,
    user_id: int,
    email_id: str,
    auth_version: int,
    *,
    token_type: str,
    ttl_seconds: int,
) -> str:
    secret = str(app_secret or "").strip()
    if not secret:
        raise RuntimeError("app_secret_missing")
    now = int(time.time())
    payload = {
        "uid": int(user_id),
        "email": str(email_id or "").strip().lower(),
        "iat": now,
        "exp": now + int(ttl_seconds),
        "jti": secrets.token_urlsafe(12),
        "ver": max(0, int(auth_version or 0)),
        "typ": token_type,
    }
    payload_raw = json.dumps(payload, separators=(",", ":"), ensure_ascii=True).encode(
        "utf-8"
    )
    payload_b64 = _b64url_encode(payload_raw)
    sig = hmac.new(
        secret.encode("utf-8"), payload_b64.encode("ascii"), hashlib.sha256
    ).digest()
    sig_b64 = _b64url_encode(sig)
    return f"v1.{payload_b64}.{sig_b64}"


def create_access_token(
    app_secret: str, user_id: int, email_id: str, auth_version: int = 0
) -> str:
    return _create_token(
        app_secret,
        user_id,
        email_id,
        auth_version,
        token_type="access",
        ttl_seconds=ACCESS_TOKEN_TTL_SECONDS,
    )


def create_refresh_token(
    app_secret: str, user_id: int, email_id: str, auth_version: int = 0
) -> str:
    return _create_token(
        app_secret,
        user_id,
        email_id,
        auth_version,
        token_type="refresh",
        ttl_seconds=REFRESH_TOKEN_TTL_SECONDS,
    )


def _verify_token_signature(app_secret: str, token: str) -> dict | None:
    """Verifica a assinatura HMAC do token e retorna o payload (sem checar expiração)."""
    secret = str(app_secret or "").strip()
    value = str(token or "").strip()
    if not secret or not value:
        return None
    parts = value.split(".")
    if len(parts) != 3 or parts[0] != "v1":
        return None
    payload_b64, sig_b64 = parts[1].strip(), parts[2].strip()
    if not payload_b64 or not sig_b64:
        return None
    expected_sig = hmac.new(
        secret.encode("utf-8"), payload_b64.encode("ascii"), hashlib.sha256
    ).digest()
    try:
        sig_raw = _b64url_decode(sig_b64)
    except Exception:
        return None
    if not hmac.compare_digest(expected_sig, sig_raw):
        return None
    try:
        payload = json.loads(_b64url_decode(payload_b64).decode("utf-8"))
    except Exception:
        return None
    if not isinstance(payload, dict):
        return None
    return payload


def verify_access_token(app_secret: str, token: str) -> dict | None:
    """Retorna payload se o token for válido e não expirado."""
    payload = _verify_token_signature(app_secret, token)
    if payload is None:
        return None
    uid = int(payload.get("uid") or 0)
    exp = int(payload.get("exp") or 0)
    token_type = str(payload.get("typ") or "access")
    if uid <= 0 or exp <= int(time.time()) or token_type != "access":
        return None
    return payload


def verify_refresh_token(app_secret: str, token: str) -> dict | None:
    payload = _verify_token_signature(app_secret, token)
    if payload is None:
        return None
    uid = int(payload.get("uid") or 0)
    exp = int(payload.get("exp") or 0)
    if (
        uid <= 0
        or exp <= int(time.time())
        or str(payload.get("typ") or "") != "refresh"
    ):
        return None
    return payload


def verify_access_token_for_refresh(app_secret: str, token: str) -> dict | None:
    """Compatibilidade nominal: somente refresh tokens dedicados são aceitos."""
    return verify_refresh_token(app_secret, token)


# Regex de e-mail — RFC 5321 simplificado: local@domain.tld
_EMAIL_RE = re.compile(
    r"^[a-zA-Z0-9!#$%&'*+/=?^_`{|}~.-]{1,64}"
    r"@"
    r"[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?"
    r"(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*"
    r"\.[a-zA-Z]{2,}$"
)


def normalize_email_id(raw: str) -> str:
    value = str(raw or "").strip().lower()
    if not value:
        raise ValueError("email_invalido")
    if not _EMAIL_RE.match(value):
        raise ValueError("email_invalido")
    return value


def normalize_login_id(raw: str, *, allow_email: bool = False) -> str:
    value = str(raw or "").strip().lower()
    if not value:
        raise ValueError("login_id_obrigatorio")
    if allow_email and "@" in value:
        return normalize_email_id(value)
    if not LOGIN_ID_RE.fullmatch(value):
        raise ValueError("login_id_invalido")
    return value


def generate_numeric_code(length: int = 6) -> str:
    size = max(4, int(length or 6))
    digits = "0123456789"
    return "".join(secrets.choice(digits) for _ in range(size))


def hash_password(raw: str) -> str:
    pwd = str(raw or "").encode("utf-8")
    salt = os.urandom(16)
    digest = hashlib.pbkdf2_hmac("sha256", pwd, salt, PWD_ITERS)
    salt_b64 = base64.urlsafe_b64encode(salt).decode("ascii").rstrip("=")
    dig_b64 = base64.urlsafe_b64encode(digest).decode("ascii").rstrip("=")
    return f"{PWD_SCHEME}${PWD_ITERS}${salt_b64}${dig_b64}"


def verify_password(raw: str, hashed: str) -> bool:
    value = str(hashed or "").strip()
    pwd = str(raw or "")
    if not value:
        return False
    if value.startswith(f"{PWD_SCHEME}$"):
        try:
            _scheme, iters_s, salt_b64, digest_b64 = value.split("$", 3)
            iters = int(iters_s)
            salt_raw = base64.urlsafe_b64decode(salt_b64 + "=" * (-len(salt_b64) % 4))
            digest_raw = base64.urlsafe_b64decode(
                digest_b64 + "=" * (-len(digest_b64) % 4)
            )
            probe = hashlib.pbkdf2_hmac(
                "sha256", pwd.encode("utf-8"), salt_raw, max(50_000, iters)
            )
            return hmac.compare_digest(probe, digest_raw)
        except Exception:
            return False

    # Compatibilidade com hashes bcrypt antigos.
    if value.startswith("$2"):
        try:
            from passlib.context import (
                CryptContext,
            )  # import tardio para evitar erro de startup

            return CryptContext(schemes=["bcrypt"], deprecated="auto").verify(
                pwd, value
            )
        except Exception:
            return False

    # Nao aceitar fallback de texto puro no backend.
    return False


def password_needs_rehash(hashed: str) -> bool:
    value = str(hashed or "").strip()
    if not value.startswith(f"{PWD_SCHEME}$"):
        return True
    try:
        _scheme, iters_s, _salt_b64, _digest_b64 = value.split("$", 3)
        return int(iters_s) < PWD_ITERS
    except Exception:
        return True


def revoke_user_sessions(db: Session, user: models.User, *, commit: bool = True) -> int:
    user.auth_version = current_auth_version(user) + 1
    if commit:
        db.commit()
        db.refresh(user)
    return current_auth_version(user)


def ensure_plan_row(db: Session, user_id: int):
    row = db.query(models.UserPlan).filter(models.UserPlan.user_id == user_id).first()
    if row:
        return row
    row = models.UserPlan(user_id=user_id, plan_code="free", trial_used=0)
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


def grant_initial_trial(db: Session, user_id: int):
    now = datetime.now(timezone.utc)
    premium_until = now + timedelta(days=1)
    db.execute(
        text(
            """
            INSERT INTO user_plan (
                user_id,
                plan_code,
                trial_used,
                updated_at
            )
            VALUES (
                :user_id,
                'free',
                0,
                :now
            )
            ON CONFLICT (user_id) DO NOTHING
            """
        ),
        {"user_id": int(user_id), "now": now},
    )
    db.execute(
        text(
            """
            UPDATE user_plan
            SET
                trial_used = 1,
                plan_code = 'trial',
                trial_started_at = :now,
                premium_until = :premium_until,
                updated_at = :now
            WHERE user_id = :user_id
              AND COALESCE(trial_used, 0) = 0
            """
        ),
        {
            "user_id": int(user_id),
            "now": now,
            "premium_until": premium_until,
        },
    )
    db.commit()
    return ensure_plan_row(db, user_id)


def encrypt_api_key(app_secret: str, value: str | None) -> str | None:
    primary = str(os.getenv("DATA_ENCRYPTION_KEY") or app_secret or "").strip()
    return security.encrypt_secret(primary, value)


def decrypt_api_key(app_secret: str, value: str | None) -> str | None:
    primary = str(os.getenv("DATA_ENCRYPTION_KEY") or app_secret or "").strip()
    candidates = [primary]
    candidates.extend(
        part.strip()
        for part in str(os.getenv("DATA_ENCRYPTION_PREVIOUS_KEYS") or "").split(",")
        if part.strip()
    )
    legacy = str(app_secret or "").strip()
    if legacy and legacy not in candidates:
        candidates.append(legacy)
    for candidate in candidates:
        try:
            return security.decrypt_secret(candidate, value)
        except ValueError:
            continue
    raise ValueError("secret_decryption_failed")


def premium_active(row: models.UserPlan | None) -> bool:
    if not row or not row.premium_until:
        return False
    premium_until = row.premium_until
    # Normaliza para timezone-aware (algumas migrações gravam datetime ingênuo).
    if (
        premium_until.tzinfo is None
        or premium_until.tzinfo.utcoffset(premium_until) is None
    ):
        premium_until = premium_until.replace(tzinfo=timezone.utc)
    return premium_until > datetime.now(timezone.utc)


def effective_streak_days(
    streak_days: int | None,
    last_activity_day: date | None,
    *,
    today: date | None = None,
) -> int:
    current_streak = max(0, int(streak_days or 0))
    if not isinstance(last_activity_day, date):
        return current_streak

    current_day = today if isinstance(today, date) else datetime.now(timezone.utc).date()
    return 0 if (current_day - last_activity_day).days >= 1 else current_streak


def apply_user_daily_activity(
    user: models.User | None,
    activity_day: date | None,
    streak_hint: int | None = None,
) -> tuple[int, date | None]:
    if user is None or not isinstance(activity_day, date):
        return 0, None

    current_streak = max(0, int(getattr(user, "streak_days", 0) or 0))
    last_day = getattr(user, "last_activity_day", None)
    if not isinstance(last_day, date):
        last_day = None
    hint = max(0, int(streak_hint or 0)) if streak_hint is not None else 0

    if last_day is None:
        next_day = activity_day
        next_streak = max(1, current_streak, hint)
    elif activity_day < last_day:
        next_day = last_day
        next_streak = max(current_streak, hint)
    elif activity_day == last_day:
        next_day = last_day
        next_streak = max(1, current_streak, hint)
    elif activity_day == (last_day + timedelta(days=1)):
        next_day = activity_day
        next_streak = max(1, current_streak + 1, hint)
    else:
        next_day = activity_day
        next_streak = max(1, hint)

    user.last_activity_day = next_day
    user.streak_days = max(0, int(next_streak))
    return int(user.streak_days or 0), user.last_activity_day


def merge_user_daily_activity(
    db: Session,
    user_id: int,
    activity_day: date | None,
    streak_hint: int | None = None,
    *,
    commit: bool = True,
) -> tuple[int, date | None]:
    user = db.query(models.User).filter(models.User.id == int(user_id)).first()
    if not user or not isinstance(activity_day, date):
        return 0, None
    streak, last_day = apply_user_daily_activity(user, activity_day, streak_hint)
    if commit:
        db.commit()
        db.refresh(user)
    return streak, last_day


def plan_duration_days(plan_code: str) -> int:
    plan = str(plan_code or "").strip().lower()
    conf = PLAN_DEFINITIONS.get(plan) or {}
    return int(conf.get("duration_days") or 0)


def activate_premium(db: Session, user_id: int, plan_code: str, *, commit: bool = True):
    plan = str(plan_code or "").strip().lower()
    days = plan_duration_days(plan)
    if days <= 0:
        return False, "Plano invalido."
    row = ensure_plan_row(db, user_id)
    base = row.premium_until
    if base and (base.tzinfo is None or base.tzinfo.utcoffset(base) is None):
        base = base.replace(tzinfo=timezone.utc)
    if not base or base <= datetime.now(timezone.utc):
        base = datetime.now(timezone.utc)
    row.plan_code = plan
    row.premium_until = base + timedelta(days=days)
    row.updated_at = datetime.now(timezone.utc)
    if commit:
        db.commit()
        db.refresh(row)
    else:
        db.flush()
    return True, "Plano ativado."


def checkout_price(plan_code: str) -> int:
    return int(PLAN_PRICES_CENTS.get(str(plan_code or "").strip().lower()) or 0)


def create_checkout_session(
    db: Session, user_id: int, plan_code: str, provider: str = "manual"
):
    plan = str(plan_code or "").strip().lower()
    amount = checkout_price(plan)
    if amount <= 0:
        return None, "Plano invalido."
    checkout_id = uuid.uuid4().hex
    auth_token = secrets.token_urlsafe(24)
    payment_code = f"QVP-{checkout_id[:8].upper()}"
    row = models.CheckoutSession(
        checkout_id=checkout_id,
        user_id=int(user_id),
        plan_code=plan,
        amount_cents=amount,
        currency="BRL",
        provider=str(provider or "manual"),
        auth_token=auth_token,
        payment_code=payment_code,
        status="pending",
        expires_at=datetime.now(timezone.utc) + timedelta(minutes=30),
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row, "Checkout criado."


def confirm_checkout_session(
    db: Session,
    user_id: int,
    checkout_id: str,
    auth_token: str,
    tx_id: str,
    provider: str = "manual",
):
    # Dados enviados pelo cliente nunca constituem prova de pagamento.
    # A liberação ocorre somente via reconciliação ou webhook autenticado.
    del db, user_id, checkout_id, auth_token, tx_id, provider
    return False, "Pagamento ainda nao verificado pelo provedor.", None


def finalize_checkout_payment(
    db: Session,
    checkout: models.CheckoutSession,
    *,
    provider: str,
    tx_id: str,
    amount_cents: int,
    currency: str = "BRL",
    plan_code: str = "",
):
    if not checkout:
        return False, "Checkout nao encontrado.", None
    tx_clean = str(tx_id or "").strip()
    if not tx_clean:
        return False, "Transacao sem identificador.", None
    provider_clean = str(provider or "manual").strip().lower() or "manual"
    amount = int(amount_cents or 0)
    curr = str(currency or "").strip().upper()
    paid_plan = str(plan_code or "").strip().lower()
    now = datetime.now(timezone.utc)

    expected_provider = str(checkout.provider or "").strip().lower()
    expected_amount = int(checkout.amount_cents or 0)
    expected_currency = str(checkout.currency or "BRL").strip().upper()
    expected_plan = str(checkout.plan_code or "").strip().lower()
    if provider_clean not in {"mercadopago", "mp"}:
        return False, "Provedor de pagamento nao verificado.", None
    if expected_provider not in {"mercadopago", "mp"}:
        return False, "Provedor divergente do checkout.", None
    if amount != expected_amount:
        return False, "Valor do pagamento divergente do checkout.", None
    if curr != expected_currency:
        return False, "Moeda do pagamento divergente do checkout.", None
    if paid_plan != expected_plan:
        return False, "Plano do pagamento divergente do checkout.", None

    payment = (
        db.query(models.Payment)
        .filter(
            models.Payment.provider == provider_clean,
            models.Payment.provider_tx_id == tx_clean,
        )
        .first()
    )
    if payment and int(payment.user_id) != int(checkout.user_id):
        return False, "Transacao pertence a outro usuario.", payment

    if str(checkout.status or "") == "confirmed":
        existing_payment = (
            db.query(models.Payment)
            .filter(
                models.Payment.provider == provider_clean,
                models.Payment.provider_tx_id == tx_clean,
            )
            .first()
        )
        if (
            existing_payment
            and int(existing_payment.user_id) == int(checkout.user_id)
            and int(existing_payment.amount_cents or 0) == expected_amount
            and str(existing_payment.currency or "").strip().upper()
            == expected_currency
            and str(existing_payment.plan_code or "").strip().lower() == expected_plan
        ):
            return True, "Checkout ja confirmado.", existing_payment
        return False, "Checkout confirmado por outra transacao.", None

    # Marca expirado se necessário
    expires_at = checkout.expires_at
    if expires_at.tzinfo is None or expires_at.tzinfo.utcoffset(expires_at) is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    if expires_at <= now:
        checkout.status = "expired"
        db.commit()
        return False, "Checkout expirado. Inicie uma nova compra.", None

    if payment and str(payment.status or "") == "paid":
        return True, "Pagamento ja registrado.", payment

    if not payment:
        payment = models.Payment(
            user_id=int(checkout.user_id),
            provider=provider_clean,
            provider_tx_id=tx_clean,
            amount_cents=amount,
            currency=curr,
            plan_code=paid_plan,
            status="paid",
            paid_at=now,
        )
        db.add(payment)

    checkout.status = "confirmed"
    checkout.confirmed_at = now
    ok, msg = activate_premium(db, int(checkout.user_id), paid_plan, commit=False)
    if not ok:
        db.rollback()
        return False, msg, None

    db.commit()
    return True, "Pagamento confirmado e premium liberado.", payment


# ── Quota / usage helpers ─────────────────────────────────────────────────────


def increment_usage_counter(db: Session, user_id: int, feature_key: str) -> None:
    """Incrementa de forma atômica o contador de uso diário (H3/H4).

    Usa UPSERT via SQL para garantir que dois requests concorrentes não
    ultrapassem o limite: a contagem é incrementada em uma única instrução
    atômica, evitando a race condition de read-increment-write em Python.
    """
    today = datetime.now(timezone.utc).date()
    db.execute(
        text(
            """
            INSERT INTO usage_daily (user_id, feature_key, day_key, used_count, updated_at)
            VALUES (:uid, :fk, :day, 1, :now)
            ON CONFLICT (user_id, feature_key, day_key)
            DO UPDATE SET
                used_count = usage_daily.used_count + 1,
                updated_at = :now
            """
        ),
        {
            "uid": int(user_id),
            "fk": str(feature_key),
            "day": today,
            "now": datetime.now(timezone.utc),
        },
    )
    db.commit()


def consume_daily_limit(
    db: Session,
    user_id: int,
    feature_key: str,
    limit: int,
    *,
    day_key: date | None = None,
) -> tuple[bool, int]:
    """Consome 1 unidade do limite diário usando o mesmo caminho atômico de UPSERT.

    Retorna (permitido, used_count_atual). O contador é incrementado antes da
    verificação para evitar race condition entre leitura e escrita.
    """
    now = datetime.now(timezone.utc)
    today = day_key or now.date()
    normalized_limit = max(0, int(limit or 0))
    if normalized_limit <= 0:
        current = (
            db.query(models.UsageDaily.used_count)
            .filter(
                models.UsageDaily.user_id == int(user_id),
                models.UsageDaily.feature_key == str(feature_key),
                models.UsageDaily.day_key == today,
            )
            .scalar()
        )
        return False, int(current or 0)
    result = db.execute(
        text(
            """
            INSERT INTO usage_daily (user_id, feature_key, day_key, used_count, updated_at)
            VALUES (:uid, :fk, :day, 1, :now)
            ON CONFLICT (user_id, feature_key, day_key)
            DO UPDATE SET
                used_count = usage_daily.used_count + 1,
                updated_at = :now
            WHERE usage_daily.used_count < :limit
            RETURNING used_count
            """
        ),
        {
            "uid": int(user_id),
            "fk": str(feature_key),
            "day": today,
            "now": now,
            "limit": normalized_limit,
        },
    )
    consumed_count = result.scalar()
    if consumed_count is None:
        used_count = int(
            db.query(models.UsageDaily.used_count)
            .filter(
                models.UsageDaily.user_id == int(user_id),
                models.UsageDaily.feature_key == str(feature_key),
                models.UsageDaily.day_key == today,
            )
            .scalar()
            or 0
        )
        db.commit()
        return False, used_count
    used_count = int(consumed_count)
    db.commit()
    return True, used_count
