"""User — same fields as the old server/db.py SQLite `users` table, now a
real SQLAlchemy model. encryption_key is still a per-user AES-256-GCM key
(server/crypto.py), unrelated to database storage — its semantics are
unchanged by this migration."""
from __future__ import annotations

import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from ...db.base import Base


def _utcnow() -> datetime.datetime:
    return datetime.datetime.now(datetime.timezone.utc)


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(320), unique=True, nullable=False, index=True)
    # Nullable since blueprint Section 4's Google Sign-In: an account
    # created via Google has no password of its own — Google already
    # verified the email, so there's nothing for us to hash. `login()`
    # (password path) and `delete_account` both check for None explicitly
    # rather than ever calling bcrypt against it.
    password_hash: Mapped[str | None] = mapped_column(String(255), nullable=True)
    display_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    encryption_key: Mapped[str] = mapped_column(String(255), nullable=False)
    # Google's stable per-user id ("sub" claim) — stored (not just the
    # email) so a future login can confirm this is genuinely the same
    # Google account even if the account's email were ever to change
    # Google-side. Unique but nullable: only set for accounts that have
    # signed in with Google at least once (a password-only account has
    # this null; an account created via Google, or a password account
    # that later links Google, has it set).
    google_sub: Mapped[str | None] = mapped_column(String(255), unique=True, nullable=True)
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    # Goes up on a password change or "sign out everywhere"; every login
    # token carries the value it was issued with and stops working once
    # they differ (core/security.py). Tokens from before this column carry
    # none and count as 0, so nobody was logged out by its introduction.
    token_version: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")

    # Optional student profile (blueprint Section 5) — every field nullable,
    # none mandatory to use the app ("sign in and immediately start
    # studying"). No exam_dates/subjects/preferred_study_times here — those
    # are structured/list-shaped and better served by real resources
    # (Goals already covers "study goals"; the rest is a real, separate,
    # deliberately deferred gap, not silently rolled into a text field).
    education_level: Mapped[str | None] = mapped_column(String(100), nullable=True)
    course: Mapped[str | None] = mapped_column(String(255), nullable=True)
    institution: Mapped[str | None] = mapped_column(String(255), nullable=True)
    preferred_language: Mapped[str | None] = mapped_column(String(50), nullable=True)
    daily_study_target_minutes: Mapped[int | None] = mapped_column(Integer, nullable=True)

    def public(self) -> dict:
        """Fields safe to send to the client on routine calls — never the
        password hash, never the encryption key repeatedly. Mirrors the old
        db.py's public_user()."""
        return {
            "id": self.id,
            "email": self.email,
            "display_name": self.display_name,
            "education_level": self.education_level,
            "course": self.course,
            "institution": self.institution,
            "preferred_language": self.preferred_language,
            "daily_study_target_minutes": self.daily_study_target_minutes,
            # So the app knows whether "change password" must ask for the
            # current one (a Google-only account sets its first instead).
            "has_password": self.password_hash is not None,
        }

    def auth_response(self) -> dict:
        """Signup/login response shape — includes encryption_key so the
        device can persist it. Mirrors the old db.py's auth_user()."""
        return {**self.public(), "encryption_key": self.encryption_key}


class PasswordResetCode(Base):
    """A 6-digit code emailed for "forgot password" (2026-10-21). Only an
    HMAC of the code is stored, so a database leak doesn't hand out live
    codes. Valid 15 minutes and for 5 tries; a new request replaces it."""

    __tablename__ = "password_reset_codes"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, unique=True, index=True
    )
    code_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    expires_at: Mapped[datetime.datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime(timezone=True), default=_utcnow, nullable=False)
