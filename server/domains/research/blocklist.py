"""Block or unblock a source without a release, and see reports.

    python -m server.domains.research.blocklist list
    python -m server.domains.research.blocklist reports
    python -m server.domains.research.blocklist add example.com "reason"
    python -m server.domains.research.blocklist add https://example.com/page "reason"
    python -m server.domains.research.blocklist remove example.com

A domain also blocks its subdomains; a full URL blocks just that page. On
the server: `study-os-blocklist <same arguments>`.
"""
from __future__ import annotations

import asyncio
import sys
from urllib.parse import urlsplit

from sqlalchemy import delete, select

from ...db.session import async_session
from .models import BlockedSource, SourceReport
from .rights import DEFAULT_BLOCKED


def _normalise(pattern: str) -> str:
    """A site address ("https://www.example.com/") blocks the whole site; a
    page address blocks just that page."""
    pattern = pattern.strip()
    if pattern.startswith("http"):
        parts = urlsplit(pattern)
        if parts.path.strip("/") or parts.query:
            return pattern
        pattern = parts.hostname or ""
    return pattern.lower().removeprefix("www.").strip("/")


async def main(args: list[str]) -> str:
    command = args[0] if args else "list"
    async with async_session() as db:
        if command == "list":
            stored = (await db.scalars(select(BlockedSource).order_by(BlockedSource.created_at))).all()
            lines = [f"{b.pattern}  — {b.reason or ''}" for b in stored]
            return "\n".join(["Blocked (added here):", *(lines or ["  none"]), f"Always blocked: {len(DEFAULT_BLOCKED)} known pirate sites"])
        if command == "reports":
            reports = (await db.scalars(select(SourceReport).order_by(SourceReport.created_at.desc()).limit(50))).all()
            return "\n".join(f"{r.created_at:%Y-%m-%d} {r.url}\n    {r.reason}" for r in reports) or "No reports."
        if command == "add" and len(args) >= 2:
            pattern = _normalise(args[1])
            if await db.scalar(select(BlockedSource).where(BlockedSource.pattern == pattern)) is None:
                db.add(BlockedSource(pattern=pattern, reason=" ".join(args[2:]) or None))
                await db.commit()
            return f"Blocked: {pattern}"
        if command == "remove" and len(args) >= 2:
            result = await db.execute(delete(BlockedSource).where(BlockedSource.pattern == _normalise(args[1])))
            await db.commit()
            return "Removed." if result.rowcount else "It wasn't on the list."
    return __doc__


if __name__ == "__main__":
    print(asyncio.run(main(sys.argv[1:])))
