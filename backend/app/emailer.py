from __future__ import annotations

import os
import smtplib
import ssl
from email.message import EmailMessage


def _env_bool(key: str, default: bool = False) -> bool:
    value = str(os.getenv(key) or "").strip().lower()
    if not value:
        return default
    return value in {"1", "true", "yes", "on"}


def smtp_configured() -> bool:
    host = str(os.getenv("SMTP_HOST") or "").strip()
    from_email = str(os.getenv("SMTP_FROM_EMAIL") or "").strip()
    return bool(host and from_email)


def send_password_reset_email(
    *,
    recipient_email: str,
    recipient_name: str,
    code: str,
    ttl_minutes: int,
    app_name: str = "Quiz Vance",
) -> None:
    host = str(os.getenv("SMTP_HOST") or "").strip()
    port = int(str(os.getenv("SMTP_PORT") or "587").strip() or 587)
    username = str(os.getenv("SMTP_USERNAME") or "").strip()
    password = str(os.getenv("SMTP_PASSWORD") or "").strip()
    from_email = str(os.getenv("SMTP_FROM_EMAIL") or "").strip()
    from_name = str(os.getenv("SMTP_FROM_NAME") or app_name).strip() or app_name
    use_ssl = _env_bool("SMTP_USE_SSL", default=False)
    use_tls = _env_bool("SMTP_USE_TLS", default=not use_ssl)

    if not host or not from_email:
        raise RuntimeError("smtp_not_configured")

    recipient_clean = str(recipient_email or "").strip().lower()
    recipient_display = str(recipient_name or "").strip() or "usuario"
    subject = f"{app_name} - codigo para redefinir sua senha"
    body = (
        f"Ola, {recipient_display}.\n\n"
        f"Seu codigo para redefinir a senha no {app_name} e: {code}\n\n"
        f"Esse codigo expira em {ttl_minutes} minutos.\n"
        "Se voce nao solicitou a redefinicao, ignore este e-mail.\n"
    )

    message = EmailMessage()
    message["Subject"] = subject
    message["From"] = f"{from_name} <{from_email}>"
    message["To"] = recipient_clean
    message.set_content(body)

    smtp_cls = smtplib.SMTP_SSL if use_ssl else smtplib.SMTP
    context = ssl.create_default_context()
    with smtp_cls(host, port, timeout=20) as server:
        if not use_ssl and use_tls:
            server.starttls(context=context)
        if username:
            server.login(username, password)
        server.send_message(message)
