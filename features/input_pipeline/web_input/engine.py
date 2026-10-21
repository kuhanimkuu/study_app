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

import ipaddress
import socket
from typing import Any
from urllib.parse import urljoin, urlsplit

import certifi
import urllib3
from bs4 import BeautifulSoup

_HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; StudyOS/0.1)"}
_TIMEOUT = urllib3.Timeout(connect=5, read=10)

# --- SSRF guard (2026-10-21) ---
# The URL comes from the user and the server fetches it, so without checks
# a user could make the server read its own private side
# (http://127.0.0.1:8000/..., other localhost services, the LAN) and get
# the reply back as "page text". Now:
#   - only http/https on the standard ports;
#   - the host is resolved once and every address must be public;
#   - the connection goes to that checked address (not a second DNS
#     lookup, which a rebinding DNS server could point somewhere else),
#     with TLS still verified against the real host name;
#   - redirects are followed by hand, each hop checked the same way;
#   - the body is capped, so a huge page can't fill the server's memory.
_ALLOWED_PORTS = {"http": 80, "https": 443}
_MAX_REDIRECTS = 5
_MAX_BODY_BYTES = 5 * 1024 * 1024


class BlockedURL(ValueError):
    """The URL points somewhere the server must not fetch."""


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


def _public_address(host: str, port: int) -> str:
    try:
        infos = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    except socket.gaierror as exc:
        raise BlockedURL(f"could not find the site {host!r}") from exc
    addresses = {info[4][0] for info in infos}
    for address in addresses:
        # is_global is False for loopback, private, link-local (cloud
        # metadata), carrier-grade NAT, multicast, reserved, unspecified...
        if not ipaddress.ip_address(address.split("%")[0]).is_global:
            raise BlockedURL("that address points to a private network, which can't be fetched")
    # Prefer IPv4: always routable from the server.
    return sorted(addresses, key=lambda a: ":" in a)[0]


def _get_once(url: str) -> urllib3.BaseHTTPResponse:
    parts = urlsplit(url)
    scheme = (parts.scheme or "").lower()
    if scheme not in _ALLOWED_PORTS:
        raise BlockedURL("only http:// and https:// links can be fetched")
    if not parts.hostname or parts.username or parts.password:
        raise BlockedURL("that isn't a valid web address")
    try:
        port = parts.port or _ALLOWED_PORTS[scheme]
    except ValueError as exc:
        raise BlockedURL("that isn't a valid web address") from exc
    if port != _ALLOWED_PORTS[scheme]:
        raise BlockedURL("only links on the standard web ports can be fetched")

    host = parts.hostname
    address = _public_address(host, port)
    if scheme == "https":
        pool = urllib3.HTTPSConnectionPool(
            address, port, timeout=_TIMEOUT, retries=False,
            server_hostname=host, assert_hostname=host,
            cert_reqs="CERT_REQUIRED", ca_certs=certifi.where(),
        )
    else:
        pool = urllib3.HTTPConnectionPool(address, port, timeout=_TIMEOUT, retries=False)
    path = parts.path or "/"
    if parts.query:
        path += "?" + parts.query
    return pool.urlopen(
        "GET", path, headers={**_HEADERS, "Host": host}, redirect=False, preload_content=False,
    )


def _fetch(url: str) -> bytes:
    for _ in range(_MAX_REDIRECTS + 1):
        response = _get_once(url)
        try:
            if response.status in (301, 302, 303, 307, 308) and response.headers.get("Location"):
                url = urljoin(url, response.headers["Location"])
                continue
            if response.status >= 400:
                raise ValueError(f"the site answered {response.status}")
            body = response.read(_MAX_BODY_BYTES + 1, decode_content=True)
            return body[:_MAX_BODY_BYTES]
        finally:
            response.release_conn()
    raise ValueError("too many redirects")


def _fetch_and_extract(url: str) -> str:
    soup = BeautifulSoup(_fetch(url.strip()), "lxml")
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
