"""Polite HTTP for the source APIs: a User-Agent that names the app and a
contact, a minimum gap between requests per host (arXiv asks for 3 s,
Open Library for at most 3 a second), a short timeout, and a database
cache so a popular topic doesn't spend quota or hammer anyone."""
from __future__ import annotations

import asyncio
import datetime
import time
import xml.etree.ElementTree as ET
from urllib.parse import urlsplit

import requests
from sqlalchemy import delete, select
from sqlalchemy.dialects.postgresql import insert

from ...db.session import async_session
from .models import ResearchCache

CONTACT = "davidmurunga27@gmail.com"
USER_AGENT = f"StudyOS/1.0 (https://studyos.helioho.st; {CONTACT})"
_TIMEOUT = 8

# Seconds between requests to one host, across the whole server process.
_MIN_GAP = {
    "export.arxiv.org": 3.0,
    "openlibrary.org": 0.4,
    "api.openalex.org": 0.15,
    "en.wikipedia.org": 0.2,
    "www.googleapis.com": 0.1,
    "www.youtube.com": 0.2,
}
_DEFAULT_GAP = 0.25
_last_call: dict[str, float] = {}
_host_locks: dict[str, asyncio.Lock] = {}


async def _wait_turn(host: str) -> None:
    lock = _host_locks.setdefault(host, asyncio.Lock())
    async with lock:
        gap = _MIN_GAP.get(host, _DEFAULT_GAP)
        wait = _last_call.get(host, 0.0) + gap - time.monotonic()
        if wait > 0:
            await asyncio.sleep(wait)
        _last_call[host] = time.monotonic()


async def get(url: str, params: dict | None = None, *, method: str = "GET", allow_redirects: bool = True) -> requests.Response:
    await _wait_turn(urlsplit(url).netloc)
    return await asyncio.to_thread(
        requests.request, method, url, params=params, timeout=_TIMEOUT,
        headers={"User-Agent": USER_AGENT, "Api-User-Agent": USER_AGENT}, allow_redirects=allow_redirects,
    )


async def get_json(url: str, params: dict | None = None):
    response = await get(url, params)
    response.raise_for_status()
    return response.json()


async def get_xml(url: str, params: dict | None = None) -> ET.Element:
    response = await get(url, params)
    response.raise_for_status()
    return ET.fromstring(response.content)


async def cached(key: str, ttl: datetime.timedelta, produce):
    """The cached value for `key`, or produce() stored for `ttl`. A failed
    produce() isn't cached (the next request tries again)."""
    now = datetime.datetime.now(datetime.timezone.utc)
    async with async_session() as db:
        hit = await db.scalar(select(ResearchCache.value).where(ResearchCache.key == key, ResearchCache.expires_at > now))
    if hit is not None:
        return hit
    value = await produce()
    async with async_session() as db:
        stmt = insert(ResearchCache).values(key=key, value=value, expires_at=now + ttl)
        await db.execute(stmt.on_conflict_do_update(index_elements=["key"], set_={"value": value, "expires_at": now + ttl}))
        await db.commit()
    return value


async def delete_expired() -> int:
    """For the cleanup worker."""
    async with async_session() as db:
        result = await db.execute(
            delete(ResearchCache).where(ResearchCache.expires_at < datetime.datetime.now(datetime.timezone.utc))
        )
        await db.commit()
    return result.rowcount or 0
