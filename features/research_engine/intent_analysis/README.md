# Intent analysis

> Status: ⏳ later phase

- **Input:** query
- **Output:** "needs external info?"

## JSON shape

Input: `{ "query": "latest research on quantum computing" }`
Output: `{ "needs_external": true, "reason": "asks for recent/current information" }`

## Notes

- Rule-based (regex/keyword matching), same honesty level as the moderator's own intent inference — no LLM in this phase. Two signal groups: recency words (`latest`/`recent`/`current`/a 202x year/etc.) and external-entity phrasing (`who is`/`what happened`/`stock price`/`election`/etc.).
- Genuinely hard to solve perfectly with keyword rules — telling "explain entropy" (timeless) apart from something that sounds timeless but actually needs current info is a real limitation, not fully solved here.
- Tested against 4 queries: recency-flagged, election-flagged, and two timeless queries (thermodynamics, algebra) all classified correctly.
- **Real bug found and fixed via a real device test session:** bare `today`/`now` used to be in the recency regex, which meant ordinary conversational phrasing like "hey how are you doing today" tripped `needs_external: true` and got routed to a live web search instead of a normal conversational reply (see moderator/README.md's general-conversation fallback, `_author_general_reply`). Removed — they're too common in everyday phrasing to be a reliable recency signal on their own, and the genuinely time-sensitive cases they were meant to catch ("what happened today", "weather today") are still caught by the external-entity regex instead.
