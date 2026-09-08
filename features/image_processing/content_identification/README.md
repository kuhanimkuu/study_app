# Content identification

> Status: ⏳ later phase

- **Input:** image
- **Output:** route → text / handwriting / math / graph / diagram / photo / table

## JSON shape

Input: `{ "image": "<path to image file>" }`
Output: `{ "route": "math", "confidence": 0.93 }` (`route` is one of `text | handwriting | math | graph | diagram | table | photo`)

## Notes

**Read this before trusting `route`.** This is a stack of cheap, real, measurable signals (OCR confidence/text via `ocr/text_ocr`, edge density, Hough-transform line geometry) combined with hand-written thresholds — **not a trained vision classifier.** `PATHWAY.md` itself flags real vision routing as Phase 4 hard-problem territory, and this project's own Android capability research (see `document_engine/scanned_ocr/README.md`) found ML Kit Image Labeling is the real, production-quality answer once there's a client to run it on. This engine is a best-effort placeholder, attempted per explicit request even though it's marked `⏳`/borderline `🚫` territory in `features.md`.

Routing logic:
1. OCR confidence ≥ 0.55 + text matches a math pattern -> `math`
2. OCR confidence ≥ 0.55, no math pattern -> `text`
3. OCR confidence in [0.20, 0.55) with some text -> `handwriting` (low OCR confidence on real text *is* the proxy signal — printed text usually OCRs cleanly, handwriting usually doesn't)
4. Dense grid of horizontal + vertical lines (≥8 each via Hough transform) -> `table`
5. At least one clear horizontal + vertical line, no dense grid -> `graph`
6. High edge density, no line/text signal -> `diagram`
7. Otherwise -> `photo`

Tested against 5 synthetic images, one per category: **text, table, graph, and photo all routed correctly.** The **math** case misrouted to `handwriting` — a genuine, demonstrated failure, not swept under the rug: Tesseract itself misread the short line `"2x + 3 = 7, solve for x"` as `"2x43 7, salve for,"` (confidence 0.41), so the low confidence correctly triggered the handwriting heuristic on what was actually badly-OCR'd printed text. This is a real, honest illustration of the whole approach's fragility — it inherits every upstream OCR mistake, and short/small-font text is exactly where OCR confidence is least reliable as a "handwriting vs printed" signal.
- `diagram` vs `photo` vs `graph` boundaries are the least validated — only one photo-like and no diagram-like test case was run. Treat this engine's output as a hint to bias toward, not a decision to trust blindly.
