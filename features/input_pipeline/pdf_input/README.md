# PDF input

> Status: ✅ core v1

- **Input:** PDF file (notes / textbook / past paper / assignment)
- **Output:** text + structure

## JSON shape

Input:
```json
{ "content": "<path to pdf file>" }
```

Output:
```json
{ "input_type": "pdf", "content": "extracted text...", "structure": { "pages": 42, "tables": [], "equations": [] } }
```

## Notes

- Composes `document_engine/pdf_processing` rather than re-implementing PDF extraction — loaded via `importlib.util.spec_from_file_location` directly from its file path (feature folders don't import each other as packages yet, see `features/README.md`; same pattern already used by `document_engine/searchable_knowledge`).
- `structure.tables`/`structure.equations` inherit `pdf_processing`'s own honesty gaps — `equations` is always `[]` (needs math OCR, not implemented), `tables` only catches ruled/gridded tables.
- Tested against `Architecture.pdf` from the repo root: correctly reported `pages: 1` and extracted text.
