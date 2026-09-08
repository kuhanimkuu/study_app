# Graph / data extraction

> Status: ⏳ later phase

- **Input:** image
- **Output:** data points

## JSON shape

Input: `{ "image": "<path to image file>" }`
Output: `{ "data": { "x": [0.0, 0.02, "..."], "y": [0.8, 0.75, "..."] }, "axis": { "x_label": "t", "y_label": "v" } }`

## Notes

**`data` is in normalized [0, 1] pixel-derived coordinates, not real axis units.** Converting to real units needs OCR'ing the numeric tick labels and matching each to its pixel position — genuinely harder (variable tick spacing, rotated labels, scientific notation) and not attempted. Returning fabricated "real" numbers without that calibration would be worse than being upfront these are normalized.

- Detects the x/y axes as the longest near-horizontal / near-vertical lines (Hough transform).
- **Assumes the curve is drawn in a color distinct from the black axes/white background** — finds it by scanning for non-grayscale pixels per column within the axis-bounded plot area. A plain black-on-white curve (same color as the axes) won't be distinguishable from the axes/gridlines by this method — a real, known limitation, not silently papered over.
- `axis.x_label`/`y_label` are a best-effort OCR guess (Tesseract) on the regions just below/left of the detected axes — not guaranteed correct, and `null` when nothing readable was found there.
- No axis/curve found at all -> honest empty result (`{"x": [], "y": []}`), not a guess.
- Tested against a synthetic sine curve (red line, black axes): correctly extracted 400 points spanning the full plot width, values in the expected [0, 1] range, and correctly OCR'd the `"time"` x-axis label.
