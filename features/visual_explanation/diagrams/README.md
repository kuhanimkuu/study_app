# Diagrams

> Status: ⏳ later phase

- **Input:** data
- **Output:** diagram (structured / editable)

## JSON shape

Input: `{ "data": { "kind": "circuit", "elements": ["battery", "resistor"], "relationships": [[0, 1]] } }` (`relationships` optional)
Output: `{ "diagram": { "kind": "circuit", "elements": [{"id": 0, "label": "battery", "x": 0, "y": 0}, "..."], "relationships": [[0, 1]] } }`

## Notes

**Produces positions/connections for a frontend to render and let the user edit — not a flat picture** (that's `visual_explanation/static_images`'s job).

- Layout is a simple, real auto-layout: elements placed left-to-right, wrapping to a new row every 4 elements. **Not** a smart graph-layout algorithm — no force-directed placement, no relationship-aware positioning. A real diagram-layout library (e.g. graphviz) would do meaningfully better, especially for non-linear relationships.
- If `relationships` isn't given, defaults to a simple sequential chain (element i connects to i+1) — a reasonable default for a linear diagram, not inferred from any real understanding of what the elements are.
- Tested with 5 elements: correctly wrapped to a second row after 4, and correctly defaulted to a 4-link sequential chain.
