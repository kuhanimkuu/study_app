# Web input

> Status: ⏳ later phase

- **Input:** URL (webpage / search query / YouTube)
- **Output:** fetched content

## JSON shape

Input: `{ "content": "https://example.com/article", "kind": "url" }` (`kind` optional, default `"url"`)
Output: `{ "input_type": "web", "content": "fetched text...", "source_url": "https://example.com/article" }`

## Notes

- Only `kind: "url"` is genuinely implemented — fetches the page (`requests`) and extracts readable text (`BeautifulSoup`, strips `script`/`style`/`nav`/`footer`/`header`/`aside`, keeps line-broken text).
- `kind: "youtube"` fetches the same way — a YouTube page's HTML has a title/description in it — but does **not** extract the video transcript, that needs a separate captions/ASR pipeline, not attempted.
- `kind: "search"` raises `NotImplementedError` rather than faking search results — real web search is `research_engine/search_pipeline`'s job, not this one's.
- Tested against `https://example.com`: correctly fetched and extracted the real page text ("Example Domain..."), stripped of markup.
