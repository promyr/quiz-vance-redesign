from datetime import date, datetime, timezone

from sqlalchemy import (
    JSON,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    LargeBinary,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from .database import Base


class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    login_id: Mapped[str] = mapped_column(
        String(190), unique=True, nullable=False, index=True
    )
    email_id: Mapped[str] = mapped_column(
        String(190), unique=True, nullable=False, index=True
    )
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    avatar_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    xp: Mapped[int] = mapped_column(Integer, default=0)
    level: Mapped[str] = mapped_column(String(50), default="Bronze")
    streak_days: Mapped[int] = mapped_column(Integer, default=0)
    auth_version: Mapped[int] = mapped_column(Integer, default=0)
    role: Mapped[str] = mapped_column(
        String(20), default="user", nullable=False, index=True
    )
    last_activity_day: Mapped[date | None] = mapped_column(nullable=True, index=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(timezone.utc)
    )


class UserPlan(Base):
    __tablename__ = "user_plan"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
        index=True,
    )
    plan_code: Mapped[str] = mapped_column(String(30), default="free")
    premium_until: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    trial_used: Mapped[int] = mapped_column(Integer, default=0)
    trial_started_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(timezone.utc)
    )


class PasswordResetToken(Base):
    __tablename__ = "password_reset_tokens"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    code_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, index=True)
    used_at: Mapped[datetime | None] = mapped_column(
        DateTime, nullable=True, index=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(timezone.utc)
    )
    __table_args__ = (
        Index("ix_password_reset_tokens_user_created", "user_id", "created_at"),
    )


class UsageDaily(Base):
    __tablename__ = "usage_daily"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    feature_key: Mapped[str] = mapped_column(String(80), nullable=False)
    day_key: Mapped[date] = mapped_column(nullable=False)
    used_count: Mapped[int] = mapped_column(Integer, default=0)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(timezone.utc)
    )
    __table_args__ = (
        UniqueConstraint("user_id", "feature_key", "day_key", name="uq_usage_daily"),
    )


class RateLimitBucket(Base):
    __tablename__ = "rate_limit_buckets"
    bucket_key: Mapped[str] = mapped_column(String(64), primary_key=True)
    window_start: Mapped[int] = mapped_column(Integer, nullable=False)
    request_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    expires_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, index=True)


class Payment(Base):
    __tablename__ = "payments"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    provider: Mapped[str] = mapped_column(String(50), nullable=False)
    provider_tx_id: Mapped[str] = mapped_column(String(190), nullable=False, index=True)
    amount_cents: Mapped[int] = mapped_column(Integer, default=0)
    currency: Mapped[str] = mapped_column(String(12), default="BRL")
    plan_code: Mapped[str] = mapped_column(String(30), default="premium_30")
    status: Mapped[str] = mapped_column(String(30), default="pending")
    paid_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(timezone.utc)
    )
    __table_args__ = (
        UniqueConstraint("provider", "provider_tx_id", name="uq_payments_provider_tx"),
        Index("ix_payments_provider_tx", "provider", "provider_tx_id"),
        Index("ix_payments_user_created", "user_id", "created_at"),
    )


class CheckoutSession(Base):
    __tablename__ = "checkout_sessions"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    checkout_id: Mapped[str] = mapped_column(
        String(64), unique=True, nullable=False, index=True
    )
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    plan_code: Mapped[str] = mapped_column(String(30), default="premium_30")
    amount_cents: Mapped[int] = mapped_column(Integer, default=0)
    currency: Mapped[str] = mapped_column(String(12), default="BRL")
    provider: Mapped[str] = mapped_column(String(50), default="manual")
    auth_token: Mapped[str] = mapped_column(String(190), nullable=False)
    payment_code: Mapped[str] = mapped_column(String(190), nullable=False)
    status: Mapped[str] = mapped_column(String(30), default="pending")
    expires_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    confirmed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(timezone.utc)
    )
    __table_args__ = (
        Index("ix_checkout_user_created", "user_id", "created_at"),
        Index("ix_checkout_status", "status"),
    )


class UserSettings(Base):
    __tablename__ = "user_settings"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
        index=True,
    )
    provider: Mapped[str] = mapped_column(String(40), default="gemini")
    model: Mapped[str] = mapped_column(String(120), default="gemini-3.5-flash")
    api_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    api_key_gemini: Mapped[str | None] = mapped_column(Text, nullable=True)
    api_key_groq: Mapped[str | None] = mapped_column(Text, nullable=True)
    economia_mode: Mapped[int] = mapped_column(Integer, default=0)
    telemetry_opt_in: Mapped[int] = mapped_column(Integer, default=0)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(timezone.utc)
    )


class AiMasterKey(Base):
    __tablename__ = "ai_master_keys"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    provider: Mapped[str] = mapped_column(String(30), nullable=False, index=True)
    label: Mapped[str] = mapped_column(String(120), nullable=False)
    secret_encrypted: Mapped[str] = mapped_column(Text, nullable=False)
    key_suffix: Mapped[str] = mapped_column(String(8), nullable=False)
    priority: Mapped[int] = mapped_column(
        Integer, default=100, nullable=False, index=True
    )
    is_active: Mapped[int] = mapped_column(
        Integer, default=1, nullable=False, index=True
    )
    health_status: Mapped[str] = mapped_column(
        String(30), default="unknown", nullable=False
    )
    failure_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    blocked_until: Mapped[datetime | None] = mapped_column(
        DateTime, nullable=True, index=True
    )
    last_tested_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    last_success_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    last_error_code: Mapped[str | None] = mapped_column(String(50), nullable=True)
    created_by_user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    __table_args__ = (
        Index(
            "ix_ai_master_keys_routing",
            "provider",
            "is_active",
            "priority",
            "blocked_until",
        ),
    )


class AdminAuditEvent(Base):
    __tablename__ = "admin_audit_events"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    actor_user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )
    action: Mapped[str] = mapped_column(String(80), nullable=False, index=True)
    target_type: Mapped[str] = mapped_column(String(50), nullable=False)
    target_id: Mapped[str | None] = mapped_column(String(80), nullable=True)
    result: Mapped[str] = mapped_column(String(30), default="success", nullable=False)
    source_ip: Mapped[str | None] = mapped_column(String(64), nullable=True)
    details_json: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
        index=True,
    )


class AdminBiometricCredential(Base):
    __tablename__ = "admin_biometric_credentials"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    credential_id: Mapped[str] = mapped_column(
        String(120), unique=True, nullable=False, index=True
    )
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    public_key: Mapped[str] = mapped_column(String(64), nullable=False)
    device_name: Mapped[str] = mapped_column(String(120), nullable=False)
    platform: Mapped[str] = mapped_column(String(30), nullable=False)
    enrolled_auth_version: Mapped[int] = mapped_column(Integer, nullable=False)
    is_active: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    last_used_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )


class AdminBiometricChallenge(Base):
    __tablename__ = "admin_biometric_challenges"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    challenge_id: Mapped[str] = mapped_column(
        String(80), unique=True, nullable=False, index=True
    )
    credential_id: Mapped[int] = mapped_column(
        ForeignKey("admin_biometric_credentials.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    scope: Mapped[str] = mapped_column(String(80), nullable=False)
    challenge: Mapped[str] = mapped_column(Text, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, index=True
    )
    used_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )


class AdminStepUpGrant(Base):
    __tablename__ = "admin_step_up_grants"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    token_hash: Mapped[str] = mapped_column(
        String(64), unique=True, nullable=False, index=True
    )
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    credential_id: Mapped[int] = mapped_column(
        ForeignKey("admin_biometric_credentials.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    scope: Mapped[str] = mapped_column(String(80), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, index=True
    )
    used_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )


class WebhookEvent(Base):
    __tablename__ = "webhook_events"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    provider: Mapped[str] = mapped_column(String(50), nullable=False)
    event_id: Mapped[str] = mapped_column(
        String(190), unique=True, nullable=False, index=True
    )
    payload_json: Mapped[str] = mapped_column(Text, nullable=False)
    processed_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(timezone.utc)
    )


class QuizStatsDaily(Base):
    __tablename__ = "quiz_stats_daily"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    day_key: Mapped[date] = mapped_column(nullable=False, index=True)
    questoes: Mapped[int] = mapped_column(Integer, default=0)
    acertos: Mapped[int] = mapped_column(Integer, default=0)
    xp_ganho: Mapped[int] = mapped_column(Integer, default=0)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(timezone.utc)
    )
    __table_args__ = (
        UniqueConstraint("user_id", "day_key", name="uq_quiz_stats_daily"),
    )


class QuizStatsEvent(Base):
    __tablename__ = "quiz_stats_events"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    event_id: Mapped[str] = mapped_column(String(120), nullable=False)
    occurred_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(timezone.utc)
    )
    questoes_delta: Mapped[int] = mapped_column(Integer, default=0)
    acertos_delta: Mapped[int] = mapped_column(Integer, default=0)
    xp_delta: Mapped[int] = mapped_column(Integer, default=0)
    correta: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(timezone.utc)
    )
    __table_args__ = (
        UniqueConstraint("user_id", "event_id", name="uq_quiz_stats_event_user"),
        Index("ix_quiz_stats_events_user_created", "user_id", "created_at"),
    )


class Flashcard(Base):
    __tablename__ = "flashcards"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    local_id: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    front: Mapped[str] = mapped_column(Text, nullable=False)
    back: Mapped[str] = mapped_column(Text, nullable=False)
    topic: Mapped[str | None] = mapped_column(String(120), nullable=True)
    interval_days: Mapped[int] = mapped_column(Integer, default=1)
    easiness: Mapped[float] = mapped_column(Float, default=2.5)
    due_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    repetitions: Mapped[int] = mapped_column(Integer, default=0)
    last_reviewed: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(timezone.utc)
    )
    __table_args__ = (
        UniqueConstraint("user_id", "local_id", name="uq_flashcard_user_local"),
        Index("ix_flashcards_user_due", "user_id", "due_date"),
    )


class QuizSeenQuestion(Base):
    """Fingerprints de perguntas já geradas para um usuário.
    Usado para instruir a IA a não repetir questões anteriores.
    """

    __tablename__ = "quiz_seen_questions"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    # Tópico normalizado (minúsculo, sem espaços duplos) para agrupamento
    topic_key: Mapped[str] = mapped_column(String(200), nullable=False)
    # SHA-1[:16] do enunciado normalizado — garante unicidade leve
    fingerprint: Mapped[str] = mapped_column(String(16), nullable=False)
    # Texto truncado em 500 chars para inserir no prompt "não repita"
    question_text: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(timezone.utc), index=True
    )
    __table_args__ = (
        UniqueConstraint(
            "user_id", "fingerprint", name="uq_quiz_seen_question_user_fp"
        ),
        Index("ix_quiz_seen_user_topic_created", "user_id", "topic_key", "created_at"),
    )


class FlashcardSeenSuggestion(Base):
    """Fingerprints de flashcards já gerados para um usuário.
    Usado para instruir a IA a não repetir flashcards anteriores.
    """

    __tablename__ = "flashcard_seen_suggestions"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    # Tópico normalizado (minúsculo, sem espaços duplos) para agrupamento
    topic_key: Mapped[str] = mapped_column(String(120), nullable=False, index=True)
    # SHA-1[:16] do front normalizado — garante unicidade leve
    fingerprint: Mapped[str] = mapped_column(String(32), nullable=False)
    # Texto truncado em 200 chars para inserir no prompt "não repita"
    front_text: Mapped[str] = mapped_column(String(200), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(timezone.utc)
    )
    __table_args__ = (
        UniqueConstraint("user_id", "fingerprint", name="uq_flashcard_seen"),
        Index("ix_flashcard_seen_user_topic", "user_id", "topic_key"),
    )


class UserAchievement(Base):
    """Conquistas desbloqueadas pelo usuário — persistidas no backend.

    Cada linha representa uma conquista única por usuário (unicidade via
    UniqueConstraint user_id + achievement_id).  O campo ``unlocked_at``
    registra quando foi desbloqueada; ``notified`` indica se já foi enviada
    como notificação push/in-app para o cliente.
    """

    __tablename__ = "user_achievements"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    achievement_id: Mapped[str] = mapped_column(String(80), nullable=False)
    title: Mapped[str] = mapped_column(String(120), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    icon: Mapped[str | None] = mapped_column(String(10), nullable=True)
    xp_reward: Mapped[int] = mapped_column(Integer, default=0)
    notified: Mapped[int] = mapped_column(Integer, default=0)  # 0=pending, 1=sent
    unlocked_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(timezone.utc), index=True
    )
    __table_args__ = (
        UniqueConstraint("user_id", "achievement_id", name="uq_user_achievement"),
        Index("ix_user_achievements_user_notified", "user_id", "notified"),
    )


class TelegramCommunityConfig(Base):
    __tablename__ = "telegram_community_config"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    chat_id: Mapped[str] = mapped_column(String(64), nullable=False)
    atualizacoes_thread_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    comece_aqui_thread_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    bate_papo_thread_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    resultados_thread_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    suporte_thread_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    feedbacks_thread_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(timezone.utc)
    )


class TelegramDailyPostLog(Base):
    __tablename__ = "telegram_daily_post_log"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    day_key: Mapped[date] = mapped_column(nullable=False, index=True)
    slot_key: Mapped[str] = mapped_column(String(40), default="08:00", nullable=False)
    topic_key: Mapped[str] = mapped_column(String(40), default="atualizacoes")
    chat_id: Mapped[str] = mapped_column(String(64), nullable=False)
    message_thread_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    post_text: Mapped[str] = mapped_column(Text, default="")
    status: Mapped[str] = mapped_column(String(20), default="pending", index=True)
    attempt_count: Mapped[int] = mapped_column(Integer, default=0)
    last_attempt_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    sent_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(timezone.utc)
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(timezone.utc)
    )
    __table_args__ = (
        UniqueConstraint(
            "day_key", "slot_key", name="uq_telegram_daily_post_log_day_slot"
        ),
    )


class TelegramInstructionPostLog(Base):
    __tablename__ = "telegram_instruction_post_log"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    day_key: Mapped[date] = mapped_column(nullable=False, index=True)
    slot_key: Mapped[str] = mapped_column(String(40), default="18:00", nullable=False)
    topic_key: Mapped[str] = mapped_column(String(40), default="comece_aqui")
    chat_id: Mapped[str] = mapped_column(String(64), nullable=False)
    message_thread_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    post_text: Mapped[str] = mapped_column(Text, default="")
    status: Mapped[str] = mapped_column(String(20), default="pending", index=True)
    attempt_count: Mapped[int] = mapped_column(Integer, default=0)
    last_attempt_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    sent_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(timezone.utc)
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(timezone.utc)
    )
    __table_args__ = (
        UniqueConstraint(
            "day_key", "slot_key", name="uq_telegram_instruction_post_log_day_slot"
        ),
    )


class StudyDocument(Base):
    """PDF privado processado de forma durável para edital ou biblioteca."""

    __tablename__ = "study_documents"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    purpose: Mapped[str] = mapped_column(String(30), nullable=False, index=True)
    file_name: Mapped[str] = mapped_column(String(255), nullable=False)
    content_type: Mapped[str] = mapped_column(
        String(80), default="application/pdf", nullable=False
    )
    size_bytes: Mapped[int] = mapped_column(Integer, nullable=False)
    sha256: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    storage_key: Mapped[str | None] = mapped_column(String(500), nullable=True)
    pdf_bytes: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    status: Mapped[str] = mapped_column(
        String(40), default="uploading", nullable=False, index=True
    )
    progress: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    page_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    cargos: Mapped[list] = mapped_column(JSON, default=list, nullable=False)
    exam_date: Mapped[str | None] = mapped_column(String(10), nullable=True)
    selected_cargo_id: Mapped[str | None] = mapped_column(
        String(120), nullable=True
    )
    selected_cargo_title: Mapped[str | None] = mapped_column(
        String(255), nullable=True
    )
    extracted_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    analysis_result: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    error_code: Mapped[str | None] = mapped_column(String(80), nullable=True)
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
        index=True,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    __table_args__ = (
        Index("ix_study_documents_user_status", "user_id", "status"),
        Index("ix_study_documents_user_created", "user_id", "created_at"),
    )


class StudyDocumentPage(Base):
    __tablename__ = "study_document_pages"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    document_id: Mapped[int] = mapped_column(
        ForeignKey("study_documents.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    page_number: Mapped[int] = mapped_column(Integer, nullable=False)
    text: Mapped[str] = mapped_column(Text, nullable=False)
    extraction_method: Mapped[str] = mapped_column(
        String(20), default="native", nullable=False
    )
    quality: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    text_sha256: Mapped[str] = mapped_column(String(64), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(timezone.utc), nullable=False
    )
    __table_args__ = (
        UniqueConstraint(
            "document_id", "page_number", name="uq_study_document_page"
        ),
        Index("ix_study_document_pages_document_page", "document_id", "page_number"),
    )


class StudyDocumentJob(Base):
    __tablename__ = "study_document_jobs"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    document_id: Mapped[int] = mapped_column(
        ForeignKey("study_documents.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    kind: Mapped[str] = mapped_column(String(30), nullable=False, index=True)
    status: Mapped[str] = mapped_column(
        String(30), default="queued", nullable=False, index=True
    )
    progress: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    attempt_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    max_attempts: Mapped[int] = mapped_column(Integer, default=3, nullable=False)
    payload: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    result: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    available_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
        index=True,
    )
    locked_by: Mapped[str | None] = mapped_column(String(120), nullable=True)
    locked_until: Mapped[datetime | None] = mapped_column(
        DateTime, nullable=True, index=True
    )
    error_code: Mapped[str | None] = mapped_column(String(80), nullable=True)
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
        index=True,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    __table_args__ = (
        Index(
            "ix_study_document_jobs_queue",
            "status",
            "available_at",
            "locked_until",
        ),
    )
