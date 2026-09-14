"""User — same fields as the old server/db.py SQLite `users` table, now a
real SQLAlchemy model. encryption_key is still a per-user AES-256-GCM key
(server/crypto.py), unrelated to database storage — its semantics are
unchanged by this migration."""
from __future__ import annotations

import datetime

from sqlalchemy import DateTime, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from ...db.base import Base


def _utcnow() -> datetime.datetime:
    return datetime.datetime.now(datetime.timezone.utc)


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(320), unique=True, nullable=False, index=True)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    display_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    encryption_key: Mapped[str] = mapped_column(String(255), nullable=False)
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )

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
        }

    def auth_response(self) -> dict:
        """Signup/login response shape — includes encryption_key so the
        device can persist it. Mirrors the old db.py's auth_user()."""
        return {**self.public(), "encryption_key": self.encryption_key}
