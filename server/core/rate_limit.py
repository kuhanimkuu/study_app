"""
Simple in-memory sliding-window rate limiter for auth endpoints (login/
signup brute-force protection — blueprint Section 37 lists "rate limiting"
as required security).

Deliberately NOT Redis-backed: this project has no shared-cache
infrastructure yet, and a single-process in-memory limiter is the
proportionate choice at this project's current scale (per Section 55.10,
"scale from evidence" — not before it's needed). Known limitation, stated
plainly rather than hidden: this does NOT protect against distributed
attacks across many source IPs, and resets on every server restart / does
not share state across multiple server processes. If this app is ever
deployed behind multiple worker processes or needs real DDoS resistance,
replace this with a Redis-backed limiter (e.g. via `slowapi` or similar)
— the call sites (`check_rate_limit`) wouldn't need to change.
"""
from __future__ import annotations

import time
from collections import defaultdict

from fastapi import HTTPException, Request

# Bounds unbounded memory growth from an attacker spraying requests across
# many distinct IPs — once the tracked-key count crosses this, keys with no
# activity in their own window are dropped. Not a precise LRU, just a
# cheap safety valve.
_MAX_TRACKED_KEYS = 10_000

_attempts: dict[str, list[float]] = defaultdict(list)


def _client_ip(request: Request) -> str:
    return request.client.host if request.client else "unknown"


def _prune_stale_keys(window_seconds: int) -> None:
    if len(_attempts) <= _MAX_TRACKED_KEYS:
        return
    cutoff = time.monotonic() - window_seconds
    stale = [key for key, times in _attempts.items() if not times or times[-1] < cutoff]
    for key in stale:
        del _attempts[key]


def check_rate_limit(request: Request, key_prefix: str, max_attempts: int, window_seconds: int) -> None:
    """Raises HTTPException(429) if `key_prefix` (e.g. "login") has been
    hit more than `max_attempts` times from this client IP within the last
    `window_seconds`. Call BEFORE doing the actual work, so a rejected
    request never reaches password verification / DB writes."""
    key = f"{key_prefix}:{_client_ip(request)}"
    now = time.monotonic()
    cutoff = now - window_seconds

    attempts = _attempts[key]
    while attempts and attempts[0] < cutoff:
        attempts.pop(0)

    if len(attempts) >= max_attempts:
        raise HTTPException(status_code=429, detail="too many attempts — please try again later")

    attempts.append(now)
    _prune_stale_keys(window_seconds)


def reset() -> None:
    """Clears all tracked attempts. Not called by the app itself — for
    tests only (see server/tests/conftest.py's autouse fixture): every
    request in the test suite shares one synthetic client IP under
    httpx's ASGITransport, so without a reset between tests the signup/
    login limits exhaust after a handful of tests regardless of real
    per-test intent. Production IP-based limiting is unaffected; this
    only clears in-memory state, which is itself per-process (see this
    module's docstring), so it's already scoped to one test run."""
    _attempts.clear()
