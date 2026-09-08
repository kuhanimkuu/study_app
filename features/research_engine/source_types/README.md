# Source types

> Status: 🚫 deferred

- **Input:** —
- **Output:** websites, YouTube, papers, images, interactive resources

## JSON shape

Input: `{ "url": "https://example.com" }`
Output: `{ "type": "website" }` (`type` is one of `website | youtube | paper | image | interactive`)

## Notes

- Rule-based domain/extension matching — real, cheap, reliable for the common cases. Falls back to `"website"` for anything unrecognized rather than guessing further.
- Tested against 5 URLs (YouTube, arXiv, an image extension, Desmos, a plain article): all classified correctly.
