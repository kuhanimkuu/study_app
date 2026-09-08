"""
Source types — classifies a URL into a source category.

INPUT (JSON) — what this engine receives:
{
    "url": "https://example.com"
}

OUTPUT (JSON) — what this engine returns:
{
    "type": "website"             # website | youtube | paper | image | interactive
}

Status: deferred / optional
Rule-based domain/extension matching — real, cheap, and reliable for the
common cases; falls back to "website" for anything unrecognized rather
than guessing further.
"""
from __future__ import annotations

import re
from typing import Any
from urllib.parse import urlparse

_YOUTUBE_DOMAINS = {"youtube.com", "www.youtube.com", "youtu.be", "m.youtube.com"}
_PAPER_DOMAINS = {"arxiv.org", "doi.org", "www.researchgate.net", "www.ncbi.nlm.nih.gov", "www.jstor.org"}
_INTERACTIVE_DOMAINS = {
    "codepen.io", "jsfiddle.net", "replit.com", "observablehq.com", "www.desmos.com", "www.geogebra.org",
}
_IMAGE_EXTENSIONS = re.compile(r"\.(jpg|jpeg|png|gif|webp|svg|bmp)$", re.IGNORECASE)


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): {"url": str}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    url: str = kwargs["url"]
    parsed = urlparse(url)
    domain = parsed.netloc.lower()
    path = parsed.path.lower()

    if domain in _YOUTUBE_DOMAINS:
        return {"type": "youtube"}
    if domain in _PAPER_DOMAINS or path.endswith(".pdf"):
        return {"type": "paper"}
    if domain in _INTERACTIVE_DOMAINS:
        return {"type": "interactive"}
    if _IMAGE_EXTENSIONS.search(path):
        return {"type": "image"}
    return {"type": "website"}


if __name__ == "__main__":
    import asyncio

    async def demo() -> None:
        for url in [
            "https://www.youtube.com/watch?v=abc123",
            "https://arxiv.org/abs/2101.00001",
            "https://example.com/diagram.png",
            "https://www.desmos.com/calculator/abc",
            "https://example.com/article",
        ]:
            result = await run(url=url)
            print(f"{url!r} -> {result}")

    asyncio.run(demo())
