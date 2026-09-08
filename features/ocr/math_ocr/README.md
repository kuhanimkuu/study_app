# Math OCR → LaTeX

> Status: ⏳ later phase (hard)

- **Input:** image (of math)
- **Output:** LaTeX equation

## JSON shape

Input: `{ "image": "<path to image file>" }`
Output: `{ "latex": "2x + 3 = 7", "confidence": 0.91 }`

## Notes

**This is genuinely hard — the project's own docs call it "the Photomath problem."** Tesseract has no concept of 2D mathematical layout (fractions, exponents as superscripts, square roots, matrices, integral bounds); it reads left-to-right like prose. This only has a real chance on simple, linear, single-line expressions.

**⚠️ `confidence > 0` does NOT mean the result is correct — read this before trusting output.** `confidence: 0.75` means only "the OCR'd text happened to be syntactically valid math that sympy could parse," not "this is what the image actually says." There is no semantic verification against the source image. **Demonstrated concretely by this engine's own test:** an image of `"x^2 / sqrt(y)"` was OCR'd as `"x42 / sqrt(y)"` (Tesseract misread `^2` as `42`) — sympy's implicit-multiplication parser then happily accepted `x42` as `x*42`, producing a confident-looking, completely wrong result: `\frac{42x}{\sqrt{y}}` instead of `\frac{x^2}{\sqrt{y}}`. This is a more dangerous failure mode than an outright parse error (which at least returns `confidence: 0`), and it is not fixed here — it's documented because it's a real, load-bearing caveat for anything downstream that consumes this engine's output.

- A simple linear equation (`"2x + 3 = 7"`) round-tripped correctly to `"2 x + 3 = 7"` with `confidence: 0.75`.
- On parse failure, `latex` falls back to the raw cleaned OCR text (which is **not** valid LaTeX) with `confidence: 0` — an honest failure signal, not a disguised guess.
- `_CLEANUP_RULES` are narrow, evidence-based character-confusion fixes (e.g. `O`/`l` misread as `0`/`1` between digits), not a general text cleanup.
- A real solution needs a model trained specifically for math recognition (e.g. an image-to-LaTeX transformer) — not attempted here given scope/resource constraints.
