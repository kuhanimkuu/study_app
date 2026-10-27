"""
The sources Go deeper searches — official APIs only, no scraping (plan
step 2, checked 25 Oct 2026; re-check terms before relying on them):

  YouTube Data API v3  videos. Needs YOUTUBE_API_KEY. search.list costs 100
                       of the default 10,000 daily units, so searches are
                       cached for a week and capped per day (YOUTUBE_DAILY_SEARCHES).
                       Videos are shown with YouTube's own embedded player,
                       never downloaded.
  OpenAlex             papers, with open-access and licence data.
  arXiv                preprints: metadata (CC0) and a link to the abstract
                       page — never the e-print itself. One request per 3 s.
  Open Library         books: metadata and a link. Light use, cached.
  Wikipedia            background reading (CC BY-SA, credited and linked).

Every function returns candidates in one shape:
  {"provider", "kind": video|paper|book|article, "title", "url", "authors",
   "year", "description", "excerpt", "licence", "attribution", ...}
and returns [] instead of raising when a provider is down or unset.
"""
from __future__ import annotations

import datetime
import logging
import re
from urllib.parse import parse_qs, quote, urlsplit

from ...core.config import get_settings
from . import fetch

logger = logging.getLogger(__name__)

WEEK = datetime.timedelta(days=7)
YOUTUBE_DAILY_SEARCHES = 90  # about 9,000 of the default 10,000 units
_youtube_searches: dict[str, int] = {}

_ARXIV = "{http://www.w3.org/2005/Atom}"


def _safe(fn):
    async def wrapper(*args, **kwargs):
        try:
            return await fn(*args, **kwargs)
        except Exception as exc:  # a provider being down never breaks Go deeper
            logger.warning("research: %s failed: %s", fn.__name__, exc)
            return []
    wrapper.__name__ = fn.__name__
    return wrapper


# --- YouTube ---------------------------------------------------------------

_VIDEO_ID_RE = re.compile(r"^[A-Za-z0-9_-]{11}$")


def youtube_video_id(url: str) -> tuple[str, int] | None:
    """(video id, start second) for a YouTube link, or None."""
    try:
        parts = urlsplit(url.strip())
    except ValueError:
        return None
    host = (parts.hostname or "").lower().removeprefix("www.").removeprefix("m.")
    video_id = None
    if host == "youtu.be":
        video_id = parts.path.strip("/").split("/")[0]
    elif host in ("youtube.com", "youtube-nocookie.com", "music.youtube.com"):
        if parts.path == "/watch":
            video_id = (parse_qs(parts.query).get("v") or [None])[0]
        else:
            match = re.match(r"^/(?:shorts|embed|live|v)/([^/?#]+)", parts.path)
            video_id = match.group(1) if match else None
    if not video_id or not _VIDEO_ID_RE.match(video_id):
        return None
    t = (parse_qs(parts.query).get("t") or parse_qs(parts.query).get("start") or ["0"])[0]
    return video_id, _seconds(t)


def _seconds(value: str) -> int:
    value = (value or "0").strip().lower()
    if value.isdigit():
        return int(value)
    match = re.fullmatch(r"(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s?)?", value)
    if not match:
        return 0
    h, m, s = (int(g or 0) for g in match.groups())
    return h * 3600 + m * 60 + s


_CHAPTER_RE = re.compile(r"^\s*[\[(]?((?:\d{1,2}:)?\d{1,2}:\d{2})[\])]?\s*[-–—:|]?\s*(.+?)\s*$")


def parse_chapters(description: str) -> list[dict]:
    """YouTube's chapters: timestamp lines in the description, the first at
    0:00, at least two. [{"start": seconds, "title"}]."""
    chapters = []
    for line in (description or "").splitlines():
        match = _CHAPTER_RE.match(line)
        if match:
            clock = [int(p) for p in match.group(1).split(":")]
            seconds = clock[-1] + 60 * clock[-2] + (3600 * clock[0] if len(clock) == 3 else 0)
            chapters.append({"start": seconds, "title": match.group(2)[:120]})
    if len(chapters) < 2 or chapters[0]["start"] != 0:
        return []
    return [c for i, c in enumerate(chapters) if i == 0 or c["start"] > chapters[i - 1]["start"]]


def _iso_duration(value: str) -> int:
    match = re.fullmatch(r"P(?:\d+D)?T?(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?", value or "")
    if not match:
        return 0
    h, m, s = (int(g or 0) for g in match.groups())
    return h * 3600 + m * 60 + s


def _video_candidate(item: dict) -> dict:
    snippet = item.get("snippet", {})
    description = snippet.get("description", "")
    channel = snippet.get("channelTitle", "")
    return {
        "provider": "youtube", "kind": "video", "title": snippet.get("title", ""),
        "url": f"https://www.youtube.com/watch?v={item['id']}", "video_id": item["id"],
        "channel": channel, "year": (snippet.get("publishedAt") or "")[:4] or None,
        "description": description, "duration": _iso_duration(item.get("contentDetails", {}).get("duration", "")),
        "chapters": parse_chapters(description), "licence": None,
        "attribution": f"“{snippet.get('title', '')}” by {channel}, on YouTube",
    }


@_safe
async def youtube_videos(topic: str, count: int = 5) -> list[dict]:
    key = get_settings().youtube_api_key
    if not key or count <= 0:
        return []
    today = datetime.date.today().isoformat()

    async def search():
        if today not in _youtube_searches:
            _youtube_searches.clear()  # a new day
        if _youtube_searches.get(today, 0) >= YOUTUBE_DAILY_SEARCHES:
            raise RuntimeError("daily YouTube search budget used up")
        _youtube_searches[today] = _youtube_searches.get(today, 0) + 1
        found = await fetch.get_json("https://www.googleapis.com/youtube/v3/search", {
            "part": "snippet", "type": "video", "q": topic, "maxResults": 8, "videoEmbeddable": "true",
            "safeSearch": "strict", "relevanceLanguage": "en", "key": key,
        })
        ids = [i["id"]["videoId"] for i in found.get("items", []) if i.get("id", {}).get("videoId")]
        if not ids:
            return []
        details = await fetch.get_json("https://www.googleapis.com/youtube/v3/videos", {
            "part": "snippet,contentDetails,status", "id": ",".join(ids), "key": key,
        })
        return [
            _video_candidate(item) for item in details.get("items", [])
            if item.get("status", {}).get("embeddable") and item.get("status", {}).get("privacyStatus") == "public"
        ]

    videos = await fetch.cached(f"youtube:search:{topic.lower()[:200]}", WEEK, search)
    return videos[:count]


@_safe
async def youtube_video(video_id: str) -> list[dict]:
    """One video's details: from the Data API when there's a key (with
    chapters), else YouTube's public oEmbed (title and channel only)."""
    key = get_settings().youtube_api_key

    async def lookup():
        if key:
            details = await fetch.get_json("https://www.googleapis.com/youtube/v3/videos", {
                "part": "snippet,contentDetails,status", "id": video_id, "key": key,
            })
            return [_video_candidate(item) for item in details.get("items", [])]
        info = await fetch.get_json("https://www.youtube.com/oembed", {
            "url": f"https://www.youtube.com/watch?v={video_id}", "format": "json",
        })
        return [{
            "provider": "youtube", "kind": "video", "title": info.get("title", ""), "video_id": video_id,
            "url": f"https://www.youtube.com/watch?v={video_id}", "channel": info.get("author_name", ""),
            "description": "", "duration": 0, "chapters": [], "licence": None,
            "attribution": f"“{info.get('title', '')}” by {info.get('author_name', '')}, on YouTube",
        }]

    return await fetch.cached(f"youtube:video:{video_id}", WEEK, lookup)


# --- OpenAlex ---------------------------------------------------------------

def _abstract(inverted: dict | None) -> str:
    if not inverted:
        return ""
    words = sorted((pos, word) for word, positions in inverted.items() for pos in positions)
    return " ".join(word for _, word in words)


@_safe
async def openalex_papers(topic: str, count: int = 4) -> list[dict]:
    if count <= 0:
        return []
    settings = get_settings()

    async def search():
        params = {
            "search": topic, "per_page": 8, "filter": "has_abstract:true,type:article|review",
            "sort": "relevance_score:desc", "mailto": fetch.CONTACT,
        }
        if settings.openalex_api_key:
            params["api_key"] = settings.openalex_api_key
        data = await fetch.get_json("https://api.openalex.org/works", params)
        papers = []
        for work in data.get("results", []):
            location = work.get("best_oa_location") or work.get("primary_location") or {}
            url = (work.get("doi") or location.get("landing_page_url") or work.get("id") or "")
            if not url.startswith("http"):
                continue
            authors = [a.get("author", {}).get("display_name", "") for a in work.get("authorships", [])[:3]]
            title = work.get("display_name") or work.get("title") or ""
            venue = (location.get("source") or {}).get("display_name")
            papers.append({
                "provider": "openalex", "kind": "paper", "title": title, "url": url,
                "authors": [a for a in authors if a], "year": work.get("publication_year"),
                "excerpt": _abstract(work.get("abstract_inverted_index")), "description": venue or "",
                "licence": location.get("license"), "open_access": bool((work.get("open_access") or {}).get("is_oa")),
                "attribution": f"{', '.join(a for a in authors if a) or 'Unknown authors'} ({work.get('publication_year')}). "
                               f"{title}. {venue or ''} — metadata via OpenAlex",
            })
        return papers

    papers = await fetch.cached(f"openalex:{topic.lower()[:200]}", WEEK, search)
    return papers[:count]


# --- arXiv ------------------------------------------------------------------

@_safe
async def arxiv_papers(topic: str, count: int = 2) -> list[dict]:
    if count <= 0:
        return []

    async def search():
        root = await fetch.get_xml("http://export.arxiv.org/api/query", {
            "search_query": f"all:{topic}", "start": 0, "max_results": 5, "sortBy": "relevance",
        })
        papers = []
        for entry in root.findall(f"{_ARXIV}entry"):
            abs_url = (entry.findtext(f"{_ARXIV}id") or "").strip().replace("http://", "https://")
            title = " ".join((entry.findtext(f"{_ARXIV}title") or "").split())
            authors = [a.findtext(f"{_ARXIV}name") or "" for a in entry.findall(f"{_ARXIV}author")][:3]
            year = (entry.findtext(f"{_ARXIV}published") or "")[:4] or None
            papers.append({
                "provider": "arxiv", "kind": "paper", "title": title, "url": abs_url, "authors": authors,
                "year": year, "excerpt": " ".join((entry.findtext(f"{_ARXIV}summary") or "").split()),
                # arXiv's metadata (title, authors, abstract) is CC0; the paper
                # itself has its own licence, so it's linked, never copied.
                "licence": "cc0", "description": "arXiv preprint",
                "attribution": f"{', '.join(authors)} ({year}). {title}. arXiv preprint — thank you to arXiv "
                               "for use of its open access interoperability.",
            })
        return papers

    papers = await fetch.cached(f"arxiv:{topic.lower()[:200]}", WEEK, search)
    return papers[:count]


# --- Open Library --------------------------------------------------------------

@_safe
async def openlibrary_books(topic: str, count: int = 2) -> list[dict]:
    if count <= 0:
        return []

    async def search():
        data = await fetch.get_json("https://openlibrary.org/search.json", {
            "q": topic, "limit": 6, "fields": "key,title,author_name,first_publish_year,edition_count",
        })
        books = []
        for doc in data.get("docs", []):
            if not doc.get("key"):
                continue
            authors = (doc.get("author_name") or [])[:2]
            books.append({
                "provider": "openlibrary", "kind": "book", "title": doc.get("title", ""),
                "url": f"https://openlibrary.org{doc['key']}", "authors": authors,
                "year": doc.get("first_publish_year"), "licence": None,
                "description": f"{doc.get('edition_count', 1)} edition(s)",
                "attribution": f"{', '.join(authors) or 'Unknown author'}, {doc.get('title', '')} "
                               f"({doc.get('first_publish_year') or 'n.d.'}) — via Open Library. "
                               "Cite the edition and page you read.",
            })
        return books

    books = await fetch.cached(f"openlibrary:{topic.lower()[:200]}", WEEK, search)
    return books[:count]


# --- Wikipedia ---------------------------------------------------------------

@_safe
async def wikipedia_articles(topic: str, count: int = 1) -> list[dict]:
    if count <= 0:
        return []

    async def search():
        found = await fetch.get_json("https://en.wikipedia.org/w/api.php", {
            "action": "query", "list": "search", "srsearch": topic, "srlimit": 2, "format": "json",
        })
        articles = []
        for hit in found.get("query", {}).get("search", []):
            title = hit.get("title", "")
            summary = await fetch.get_json(f"https://en.wikipedia.org/api/rest_v1/page/summary/{quote(title.replace(' ', '_'))}")
            url = summary.get("content_urls", {}).get("desktop", {}).get("page")
            if not url or summary.get("type") == "disambiguation":
                continue
            articles.append({
                "provider": "wikipedia", "kind": "article", "title": summary.get("title", title), "url": url,
                "excerpt": summary.get("extract", ""), "description": summary.get("description") or "",
                "licence": "cc-by-sa-4.0",
                "attribution": f"“{summary.get('title', title)}”, Wikipedia — text under CC BY-SA 4.0 "
                               "(creativecommons.org/licenses/by-sa/4.0)",
            })
        return articles

    articles = await fetch.cached(f"wikipedia:{topic.lower()[:200]}", WEEK, search)
    return articles[:count]
