"""
Search pipeline — search -> discover -> fetch -> parse -> clean -> rank ->
dedupe -> extract, producing curated sources.

INPUT (JSON) — what this engine receives:
{
    "query": "quantum computing basics"
}

OUTPUT (JSON) — what this engine returns:
{
    "sources": [
        {"title": "...", "url": "...", "snippet": "...", "rank": 1}
    ]
}

Status: deferred / optional (server-class work) — attempted best-effort
per explicit request, not a full solution.

HONESTY NOTE: this is real, working search (queries DuckDuckGo's HTML
endpoint, which needs no API key, and parses actual result links/titles/
snippets) — not fabricated results. But it is NOT the "server-class"
pipeline the original feature name implies: no result caching, no
rate-limit/backoff handling, no robust anti-bot evasion, no JS-rendered
page support, no per-domain politeness delays, single-search-engine only.
It's the "search" and "rank" (by result order) and "dedupe" (by URL) steps
of the pipeline description; "discover -> fetch -> parse -> clean ->
extract" full page content per result is NOT done here — reuse
input_pipeline/web_input on a chosen source's URL for that, deliberately
kept as a separate step rather than fetching every result's full page
content on every search (that's the expensive part "server-class" alludes
to, and doing it eagerly for every result would be wasteful when the
caller likely only wants one or two of them fetched in full).
"""
from __future__ import annotations

from typing import Any

import requests
from bs4 import BeautifulSoup

_SEARCH_URL = "https://html.duckduckgo.com/html/"
_HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; StudyOS/0.1)"}
_TIMEOUT = 10


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): {"query": str}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    query: str = kwargs["query"]

    response = requests.post(_SEARCH_URL, data={"q": query}, headers=_HEADERS, timeout=_TIMEOUT)
    response.raise_for_status()

    sources = _parse_results(response.text)
    return {"sources": sources}


# --- private helpers ---


def _parse_results(html: str) -> list[dict]:
    soup = BeautifulSoup(html, "lxml")
    results = soup.select(".result")

    sources = []
    seen_urls = set()
    rank = 1
    for result in results:
        link = result.select_one(".result__a")
        snippet_el = result.select_one(".result__snippet")
        if link is None:
            continue

        url = link.get("href", "")
        title = link.get_text(strip=True)
        snippet = snippet_el.get_text(strip=True) if snippet_el else ""

        if not url or url in seen_urls:
            continue
        seen_urls.add(url)

        sources.append({"title": title, "url": url, "snippet": snippet, "rank": rank})
        rank += 1

    return sources


if __name__ == "__main__":
    import asyncio

    async def demo() -> None:
        result = await run(query="quantum computing basics")
        print(f"{len(result['sources'])} sources found:")
        for source in result["sources"][:5]:
            print(f"  [{source['rank']}] {source['title']} -> {source['url']}")

    asyncio.run(demo())
