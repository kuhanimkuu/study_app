# PDF processing

> Status: ✅ core v1

- **Input:** PDF file
- **Output:** metadata, text, page structure, images, tables, equations

## JSON shape

Input:
```json
{ "pdf": "<path to pdf file>" }
```

Output:
```json
{
    "metadata": { "title": "...", "author": "...", "subject": "...", "page_count": 1 },
    "text": "full extracted text...",
    "pages": [ { "number": 1, "text": "..." } ],
    "tables": [ { "page": 1, "rows": [["cell", "cell"], ["cell", "cell"]] } ],
    "equations": []
}
```

## Notes

- Built on PyMuPDF (`fitz`), already installed in this environment.
- `tables` uses `page.find_tables()` — works for ruled/gridded tables, not guaranteed for borderless ones.
- `equations` is always `[]` for now — extracting them needs math OCR (`features/ocr/math_ocr`, not yet implemented).
- Image extraction (from the original feature list) is not implemented — only text/metadata/pages/tables.
- Tested against `Architecture.pdf` and `study_os_overview-v2.pdf` from the repo root: run `python engine.py <path-to-pdf>`.
