"""
Web input — accepts a URL and fetches its readable text content.

INPUT (JSON) — what the input layer receives:
{
    "content": "https://example.com/article",
    "kind": "url"                # url | search | youtube
}

OUTPUT (JSON) — what this engine returns to the moderator:
{
    "input_type": "web",
    "content": "fetched text...",
    "source_url": "https://example.com/article"
}

Status: later phase

Only "kind": "url" is genuinely implemented — fetches the page and extracts
readable text (strips script/style/nav/footer, keeps paragraph-ish text).
"kind": "youtube" fetches the same way (a YouTube page's HTML has a title
and description in it) but does NOT extract the video transcript — that
needs a separate captions/ASR pipeline, not attempted. "kind": "search"
raises NotImplementedError rather than faking search results — real web
search is research_engine/search_pipeline's job (see that engine's
"server-class work" caveat), not this one's.
"""
from __future__ import annotations

from typing import Any

import requests
from bs4 import BeautifulSoup

_HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; StudyOS/0.1)"}
_TIMEOUT = 10


async def run(**kwargs: Any) -> dict:
    """Sole entry point the input layer calls.

    Args (kwargs): {"content": "<url>", "kind"?: "url" | "search" | "youtube"}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    url: str = kwargs["content"]
    kind: str = kwargs.get("kind", "url")

    if kind == "search":
        raise NotImplementedError(
            "web_input does not perform search itself — that's research_engine/search_pipeline's job."
        )

    text = _fetch_and_extract(url)
    return {"input_type": "web", "content": text, "source_url": url}


# --- private helpers ---


def _fetch_and_extract(url: str) -> str:
    response = requests.get(url, headers=_HEADERS, timeout=_TIMEOUT)
    response.raise_for_status()

    soup = BeautifulSoup(response.text, "lxml")
    for tag in soup(["script", "style", "nav", "footer", "header", "aside"]):
        tag.decompose()

    text = soup.get_text(separator="\n")
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    return "\n".join(lines)


if __name__ == "__main__":
    import asyncio
    import sys

    url = sys.argv[1] if len(sys.argv) > 1 else None
    if not url:
        print(f"[{__name__}] usage: python engine.py <url>")
    else:
        result = asyncio.run(run(content=url))
        enc = sys.stdout.encoding or "utf-8"
        print("source_url:", result["source_url"])
        print("content length:", len(result["content"]))
        print("first 300 chars:", result["content"][:300].encode(enc, errors="replace").decode(enc))
