# Table extraction

> Status: ⏳ later phase

- **Input:** image / pdf
- **Output:** structured table

## JSON shape

Input: `{ "image": "<path to image or pdf file>" }`
Output: `{ "table": { "headers": ["Name", "Value"], "rows": [["x", "2"], ["y", "3"]] } }`

## Notes

- `.pdf` input delegates to `document_engine/pdf_processing`'s own table detection (PyMuPDF's `find_tables`) rather than reimplementing it.
- Image input is **real grid-based extraction**, not fake: detects ruled grid lines via OpenCV morphological line detection (erode/dilate with long thin kernels), clusters them into row/column boundaries, then OCRs each resulting cell individually with Tesseract.
- **Only works for tables with visible ruling lines.** A borderless/whitespace-aligned table returns `{"headers": [], "rows": []}` — an honest empty result rather than a guess, since inferring cell boundaries from text alignment alone is a materially harder, unimplemented problem.
- **Real bug found and fixed via testing:** cropping cells exactly at the detected line boundaries fed Tesseract crops containing border-line pixels, which made it return empty text entirely (verified: the identical cell crop returned `""` with a few border pixels included, `"Name"` with an 8px inset). Cell crops are now inset by `CELL_INSET = 8` pixels on each side before OCR.
- Tested against a synthetic 2x3 ruled table image: headers and all rows extracted exactly correctly (`["Name", "Value"]` / `[["x", "2"], ["y", "3"]]`).
