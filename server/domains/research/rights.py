"""
What the app may do with a source (Study OS plan step 3) — decided by
fixed rules here, never by the model. Default: link only.

  A  open: public domain, CC0, CC BY or CC BY-SA, read from the licence field
     of a trusted API (OpenAlex, arXiv metadata, Wikipedia). May show a short
     excerpt, always with attribution and the licence.
  B  everything else: unclear or copyrighted (textbooks, videos, most web
     pages). Title, source, a short description and the link; the model may
     teach the idea in its own words with a citation. Any quoted text is cut
     to QUOTE_LIMIT_B characters in code.
  C  blocked: shadow libraries and pirate sites, and anything on the
     blocklist (blocked_sources table or the defaults below). Never shown,
     never given to the model.

A licence claimed on an untrusted page counts for nothing: tier A needs both
an open licence and a source on the trusted list. Non-commercial licences
(CC BY-NC, e.g. OpenStax) are not tier A in a paid app.

This lowers the risk; it doesn't remove it. Where the line is for quotes
(US fair use, EU exceptions) is a question for a lawyer.
"""
from __future__ import annotations

from urllib.parse import urlsplit

from sqlalchemy import select

from ...db.session import async_session
from .models import BlockedSource

QUOTE_LIMIT_A = 600
QUOTE_LIMIT_B = 200

# Sources whose licence metadata the app trusts.
TRUSTED_LICENCE_SOURCES = {"openalex", "arxiv", "wikipedia"}

_OPEN_LICENCES = {
    "public-domain": "Public domain",
    "publicdomain": "Public domain",
    "cc0": "CC0",
    "cc-by": "CC BY",
    "cc-by-sa": "CC BY-SA",
}

# Always tier C, whatever a search returns.
DEFAULT_BLOCKED = {
    "libgen.is", "libgen.rs", "libgen.li", "library.lol", "z-lib.org", "z-library.se", "zlibrary.to", "1lib.sk",
    "sci-hub.se", "sci-hub.st", "sci-hub.ru", "annas-archive.org", "annas-archive.se", "pdfdrive.com",
    "b-ok.cc", "bookfi.net", "vdoc.pub", "dokumen.pub", "epdf.pub", "ebin.pub",
}


def normalise_licence(raw: str | None) -> str | None:
    if not raw:
        return None
    value = raw.strip().lower().replace(" ", "-").replace("_", "-")
    value = value.removeprefix("https://creativecommons.org/licenses/").removeprefix("http://creativecommons.org/licenses/")
    for prefix in ("cc-by-nc", "by-nc"):
        if value.startswith(prefix):
            return "CC BY-NC"
    if value.startswith("by-sa") or value.startswith("cc-by-sa"):
        return "CC BY-SA"
    if value.startswith("by-nd") or value.startswith("cc-by-nd"):
        return "CC BY-ND"
    if value.startswith("by/") or value in ("by", "cc-by") or value.startswith("cc-by-4") or value.startswith("cc-by-3"):
        return "CC BY"
    for key, label in _OPEN_LICENCES.items():
        if value.startswith(key):
            return label
    return raw.strip()[:80]


def _host(url: str) -> str:
    return (urlsplit(url).hostname or "").lower().removeprefix("www.")


async def blocked_patterns() -> set[str]:
    async with async_session() as db:
        stored = set((await db.scalars(select(BlockedSource.pattern))).all())
    return DEFAULT_BLOCKED | stored


def is_blocked(url: str, patterns: set[str]) -> bool:
    """`patterns` adds to the built-in pirate-site list, never replaces it."""
    host = _host(url)
    if url in patterns:
        return True
    return any(host == p or host.endswith("." + p) for p in DEFAULT_BLOCKED | patterns if "/" not in p)


def classify(source: dict, patterns: set[str]) -> str:
    """'A', 'B' or 'C' for a candidate {"url", "provider", "licence", ...}."""
    if is_blocked(source["url"], patterns):
        return "C"
    licence = normalise_licence(source.get("licence"))
    if source.get("provider") in TRUSTED_LICENCE_SOURCES and licence in ("Public domain", "CC0", "CC BY", "CC BY-SA"):
        return "A"
    return "B"


def apply_tier(source: dict, tier: str) -> dict:
    """Trims what may be shown: an excerpt only for tier A (with its
    attribution), a short description for tier B."""
    out = dict(source, tier=tier, licence=normalise_licence(source.get("licence")))
    text = (source.get("excerpt") or "").strip()
    if tier == "A" and text:
        out["excerpt"] = text[:QUOTE_LIMIT_A] + ("…" if len(text) > QUOTE_LIMIT_A else "")
    else:
        out.pop("excerpt", None)
        description = (source.get("description") or "").strip()
        out["description"] = description[:QUOTE_LIMIT_B] + ("…" if len(description) > QUOTE_LIMIT_B else "")
    return out
