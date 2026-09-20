# Interactive 2D

> Status: ⏳ later phase

- **Input:** data
- **Output:** interactive visual (SVG / canvas / native)

## JSON shape

Input, one of: `{ "data": { "points": { "x": [...], "y": [...] } } }` or `{ "expression": "sin(x)", "range": [-10, 10] }`
Output: `{ "visual": { "type": "2d", "data": { "points": {...} }, "interactive": true } }`

## Notes

- The actual interactivity (hover/zoom/pan) is a rendering concern for whatever renders this JSON on the frontend — this engine's real job is producing correctly-shaped, real point data for it to render, not implementing interactivity itself (that can't happen server-side).
- Composes `math_engine/graphing` (via `importlib`) when given an `expression` rather than raw points, instead of duplicating point-generation logic.
- Tested with `expression: "sin(x)"`: correctly returned 200 real points and `interactive: true`.
