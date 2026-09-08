# Static images

> Status: ✅ core v1 — including a real `format: "pdf"` path (matplotlib's Agg backend saves vector PDF natively, not a raster-to-PDF conversion), reachable from chat via `moderator/engine.py`'s `_route_static_image`

- **Input:** data
- **Output:** image (PNG / JPEG / WebP / **PDF**)

## JSON shape

Input: `{ "data": { "points": { "x": [...], "y": [...] }, "title": "y = x^2" }, "format": "png", "output_path": "graph.png" }` (`format`/`output_path` optional)
Output: `{ "image": "<path to generated image file>", "format": "png" }`

## Notes

- Built on matplotlib (headless `Agg` backend — appropriate for a server with no display). A real render, not a placeholder file.
- Point data matches `math_engine/graphing`'s output shape directly — feed that engine's `points` straight into this one's `data.points`.
- Tested: generated a real 19.8KB PNG from a parabola's point data, confirmed the file exists and has real content (non-trivial size).
- **PDF export, built on request** ("draw a graph of y=3x+2, and also generate its pdf for download") — verified end-to-end through the actual moderator route: a real 7.8KB PDF with correct `%PDF` header and `%%EOF` trailer, not an empty stub. Emitted as a `"pdf"` block (same shape `document_generation/generate_docs` already produces), so the Flutter client's existing `PdfBlockView` renders it — no new widget needed.
