# OCR on scanned pages

> Status: ⏳ later phase

- **Input:** PDF (scanned)
- **Output:** text

## JSON shape

Input:
```json
{ "pdf": "<path to pdf file>", "pages": [3, 4, 5] }
```
`pages` is optional — omit it to scan every page in the document.

Output:
```json
{ "text": { "3": "page 3 text...", "4": "page 4 text..." } }
```
Only pages that were detected as scanned (image-only, no real text layer) and OCR'd appear as keys — a page with a normal text layer is silently skipped.

## Notes

- Built on PyMuPDF (`fitz`) for page detection/rasterization + `pytesseract` for OCR.
- **Requires the Tesseract engine binary on PATH** (pytesseract is only a Python wrapper around it) — install from https://github.com/tesseract-ocr/tesseract. Installed locally in this environment (user-level, added to user PATH); `engine.py`'s `__main__` block catches `TesseractNotFoundError` and tells you to install it rather than crashing if it's missing.
- Detection heuristic (`_is_scanned_page`): a page counts as "scanned" if it has fewer than `TEXT_LAYER_THRESHOLD` (20) characters of real extractable text *and* contains at least one embedded image. Tune the threshold if it misfires on real scans.
- Deliberately does **not** reuse `pdf_processing`'s text extraction — it only rasterizes pages that `pdf_processing` would find empty.
- Tested against `Architecture.pdf` and `study_os_overview-v2.pdf` (both real text PDFs): correctly detects 0 scanned pages in each — no false positives. Also verified against a synthetic image-only PDF: correctly flagged as scanned and OCR'd the embedded text accurately.

### Platform note: server-hosted, not on-device (superseded the earlier Chaquopy caveat)

Earlier draft of this note flagged `pytesseract`'s subprocess-to-native-binary model as a blocker for an on-device Chaquopy port, and PyMuPDF's Chaquopy support as unverified (confirmed via chaquo.com/pypi-13.1: PyMuPDF is in fact **not** in Chaquopy's supported native-package list). That's moot now — the project direction is a **server-hosted backend**: this engine runs as ordinary Python on a server, and the Android app is a thin client sending images/PDFs over HTTP. No Chaquopy/on-device native-package constraints apply. PyMuPDF + pytesseract (with the real Tesseract binary on the server) work as-is.

If a genuinely on-device/offline fallback is ever wanted later, the Android-native path is still: `android.graphics.pdf.PdfRenderer` (rasterize) + ML Kit Text Recognition v2 (OCR), both native, no Python involved — see the Android capability research from this session if that doc gets written up.
