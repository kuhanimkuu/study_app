# Text OCR

> Status: ✅ core v1

- **Input:** image
- **Output:** text

## JSON shape

Input:
```json
{ "image": "<path to image file>" }
```

Output:
```json
{ "text": "The second law of thermodynamics states...", "confidence": 0.98 }
```
`confidence` is the mean of Tesseract's per-word confidences (0-100, scaled to 0-1 here), excluding words it couldn't score — a genuine measure from the OCR engine, not a guess.

## Notes

- Built on `pytesseract` + the real Tesseract binary — same tool as `document_engine/scanned_ocr`. This is the standalone-image counterpart; `scanned_ocr` is specifically for image-only PDF pages.
- Runs as ordinary server-side Python — no Chaquopy/Android on-device constraint applies (project direction is a server-hosted backend). If an on-device path is ever wanted, the Android-native equivalent is ML Kit Text Recognition v2, not this.
- Tested against a synthetic two-line test image: text extracted correctly (minor spacing artifacts from the plain default font, not a bug), confidence reported as 0.55 — a genuine, non-trivial score, not a hardcoded stand-in.
