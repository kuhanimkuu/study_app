"""
Settings — reads DATABASE_URL (and anything else config-shaped) from the
environment / a local .env file. See STUDY_OS_PROGRESS.md's 2026-09-14
hosting/DB decision: PostgreSQL from day one (HelioHost deployment target),
no SQLite, app is not offline-capable.

.env is gitignored (same pattern as server/.jwt_secret, server/.encryption_key
— see .gitignore) — .env.example documents the shape without real values.
"""
from __future__ import annotations

from functools import lru_cache

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # asyncpg driver — SQLAlchemy's async engine requires the "+asyncpg"
    # dialect suffix, not a plain "postgresql://" URL.
    database_url: str = "postgresql+asyncpg://study_os_app:study_os_app@localhost:5432/study_os"

    @field_validator("database_url")
    @classmethod
    def _ensure_asyncpg_driver(cls, value: str) -> str:
        # A managed-Postgres host (Render, Railway, ...) hands you a plain
        # "postgresql://" connection string via its own env var/reference —
        # normalize it here rather than requiring every hosting provider's
        # config to know this app's driver choice.
        if value.startswith("postgresql://"):
            return "postgresql+asyncpg://" + value[len("postgresql://"):]
        return value

    # Comma-separated origins, e.g. "https://app.example.com,https://staging.example.com".
    # Defaults to "*" (every origin) so local dev against the Flutter app
    # keeps working with zero setup — main.py's own comment already flagged
    # this as "tighten before real deployment"; this makes that an .env
    # change instead of a code change, closing the actual gap (no way to
    # tighten it without editing source) rather than just moving the TODO.
    cors_allowed_origins: str = "*"

    @property
    def cors_allowed_origins_list(self) -> list[str]:
        if self.cors_allowed_origins.strip() == "*":
            return ["*"]
        return [origin.strip() for origin in self.cors_allowed_origins.split(",") if origin.strip()]

    # The "Web application" OAuth client id (blueprint Section 4, Google
    # Sign-In) — this is the token *audience* the app's Android-side
    # google_sign_in plugin requests via `serverClientId`, and what the
    # server verifies every Google ID token against. Deliberately not the
    # Android OAuth client's own id: that one is matched by Google Play
    # Services automatically from the app's package name + signing
    # certificate and never appears in code on either side. Empty by
    # default so a server with no Google OAuth configured at all still
    # starts cleanly; POST /api/auth/google fails clearly if this is unset
    # rather than silently accepting unverifiable tokens.
    google_oauth_client_id: str = ""

    # Hosted pay-as-you-go AI tier (blueprint Section 42.1) — see
    # server/domains/billing/ and STUDY_OS_PROGRESS.md's 2026-09-20 entry.
    # "mock" is the only implemented value until a real payment processor
    # is chosen (server/domains/billing/payment_provider.py raises a clear
    # error for any other value rather than silently no-opping).
    payment_provider: str = "mock"
    # Percent markup on top of the pooled provider's own raw usage cost —
    # see billing/pricing.py's compute_charge. Kept separate from
    # hosted_infra_surcharge_percent below per the user's explicit
    # instruction that Study OS's own hosting cost be a distinct,
    # independently-adjustable line item, not blended into one number.
    hosted_markup_percent: float = 30.0
    # Percent surcharge covering Study OS's own server/hosting cost (e.g.
    # HelioHost/Render). Starts at 0 — the real number is a business
    # decision for once actual hosting costs under real usage are known,
    # not a default to guess at; the knob is fully wired end-to-end now
    # so setting it later needs only an .env change, not a code change.
    hosted_infra_surcharge_percent: float = 0.0

    # Study OS's OWN pooled provider API keys for the hosted tier —
    # distinct from a user's manually-entered BYOK key (which is
    # per-user, client-encrypted via crypto.py, and never stored here).
    # Empty by default so a server with no hosted tier configured still
    # starts cleanly; resolve_model_config (core/model_config.py) fails
    # clearly if a user requests backend="hosted" for a provider with no
    # key configured, rather than silently using an empty key.
    hosted_anthropic_api_key: str = ""
    hosted_openai_api_key: str = ""
    hosted_deepseek_api_key: str = ""


@lru_cache
def get_settings() -> Settings:
    return Settings()
