# Handwriting recognition

> Status: ⏳ later phase

- **Input:** image
- **Output:** text

## JSON shape

Input: `{ "image": "<path to image file>" }`
Output: `{ "text": "Solve for x", "confidence": 0.87 }`

## Notes

**Not a specialized handwriting model — this is plain Tesseract** (same engine as `ocr/text_ocr`), which is trained primarily on printed fonts. Real handwriting/cursive recognition needs a dedicated model (e.g. a transformer-based one like TrOCR); none is installed here given scope/resource constraints. ML Kit's Digital Ink Recognition (confirmed during this project's Android capability research) doesn't solve this either — it recognizes live stylus/touch strokes, not photos of handwriting on paper.

The one real adjustment vs `text_ocr`: `--psm 6` (assume a single uniform text block) instead of Tesseract's default page-segmentation mode.

Tested against a printed (not truly handwritten) test image as a smoke test: ran without error; Tesseract itself misread "Solve for x" as "Salve forx" — a real, expected illustration of the limitation documented above, not hidden.
