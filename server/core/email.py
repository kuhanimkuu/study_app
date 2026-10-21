"""Sending email through Resend's HTTP API (https://resend.com/docs/api-reference/emails/send-email).
Used only for "forgot password" codes. Blocking; call via asyncio.to_thread."""
from __future__ import annotations

import logging

import requests

from .config import get_settings

logger = logging.getLogger(__name__)

_RESEND_URL = "https://api.resend.com/emails"


def email_configured() -> bool:
    return bool(get_settings().resend_api_key)


def send_email(to: str, subject: str, text: str, html: str) -> None:
    settings = get_settings()
    response = requests.post(
        _RESEND_URL,
        headers={"Authorization": f"Bearer {settings.resend_api_key}"},
        json={"from": settings.email_from, "to": [to], "subject": subject, "text": text, "html": html},
        timeout=15,
    )
    if response.status_code >= 300:
        # Never log the address or the code; Resend's own message is enough
        # to see what's wrong (unverified domain, bad key...).
        logger.warning("email: Resend refused a message: %s %s", response.status_code, response.text[:300])
        response.raise_for_status()
