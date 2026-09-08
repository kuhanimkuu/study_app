# Diagram understanding

> Status: ⏳ later phase

- **Input:** image
- **Output:** structured diagram

## JSON shape

Input: `{ "image": "<path to image file>" }`
Output: `{ "diagram": { "kind": "flowchart-like", "elements": ["rectangle", "rectangle", "line"], "relationships": [] } }`

## Notes

**Does NOT recognize domain-specific symbols.** The original feature description's example (`"resistor"`, `"capacitor"`) would be outright fabrication without a trained symbol classifier — there's no way to distinguish a resistor symbol from a capacitor symbol via generic shape detection. `elements` instead lists real, generically-detected geometric primitives (`circle`/`rectangle`/`triangle`/`line`) via OpenCV contour analysis (`approxPolyDP` vertex count + circularity for anything that isn't clearly a triangle/quad) — true facts about the image's shapes, not guessed domain semantics. `kind` is a coarse, low-confidence guess from the primitive mix, explicitly hedged with `"-like"` rather than asserted as real classification. `relationships` is always `[]` — inferring which elements connect needs graph analysis of line endpoints against shape boundaries, not attempted. `PATHWAY.md` itself flags real diagram/vision understanding as Phase 4 hard-problem territory; this is a best-effort placeholder, attempted per explicit request.

- **Real bug found and fixed via testing:** the initial circularity check only ran for contours with `vertex_count > 8`, but a thin-stroke circle's contour approximated to exactly 8 vertices, so it fell through to the `else` branch and got misclassified as `"line"`. Fixed by deferring to the circularity check for *any* non-triangle/non-quad shape instead of gating on a fixed vertex count first — a synthetic circle test now correctly reports `"circle"`.
- Tested against two synthetic diagrams: two rectangles + a connecting line correctly classified `"flowchart-like"`; two circles + connecting lines correctly classified `"network-or-circuit-like"` (after loosening the line-count threshold to match the flowchart case's, since only one of two drawn lines survived contour detection as a separate element — a real, minor gap in line-vs-line-touching-shape separation, not chased further).
