# Search pipeline

> Status: 🚫 deferred (server-class work)

- **Input:** query
- **Output:** curated sources (discover → fetch → parse → clean → rank → dedupe → extract)

## JSON shape

Input: `{ "query": "quantum computing basics" }`
Output: `{ "sources": [ { "title": "...", "url": "...", "snippet": "...", "rank": 1 } ] }`

## Notes

**Real, working search — not fabricated results.** Queries DuckDuckGo's HTML endpoint (`html.duckduckgo.com/html/`, no API key needed) and parses actual result titles/links/snippets.

**But this is not the "server-class" pipeline the original feature name implies** — no result caching, no rate-limit/backoff handling, no robust anti-bot evasion, no JS-rendered page support, no per-domain politeness delays, single search engine only. It covers "search" + "rank" (by result order) + "dedupe" (by URL); it does **not** fetch/parse/clean each result's full page content — that's `input_pipeline/web_input`'s job on a chosen source's URL, kept as a deliberately separate step rather than eagerly fetching every result's full page on every search (wasteful when the caller likely only wants one or two fetched in full).

- Tested live against `"quantum computing basics"`: returned 10 real, relevant, deduplicated sources (Wikipedia, IBM, GeeksforGeeks, and others), correctly ranked by result order.
