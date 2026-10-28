# Document generation / PDF output

> Status: ✅ wired up. The Studio tab (`POST /api/projects/{slug}/studio`, server/domains/knowledge/router.py) and chat's "... as a pdf" requests (moderator `_route_write_doc`) both use it, and so does the chat flashcard route's printable copy.

- **Input:** a spec written by the AI, or raw material
- **Output:** a designed PDF: study guide, revision notes, summary, formula sheet, worksheet, flashcards, practice exam, lab report

## How it works: templates (redesigned 2026-10-28)

Until 2026-10-28 every document was the material printed as one black bullet per chunk. Now each type is a **template**:

| File | Job |
|---|---|
| `templates.py` | One entry per doc_type: what the AI is asked to write (the plan of sections and blocks), its colour and layout options (numbered sections, a name/date line, lines to write on, the answer page's title), and `max_tokens`. Also `SPEC_SCHEMA`, the one JSON shape every template asks for. |
| `render.py` | Draws a spec with reportlab: a coloured title band, numbered section bars, callout boxes (tip, watch out, remember, worked example, key idea), glossary tables, formula boxes, tables, questions with marks/options/answer lines, cut-out flashcards, fill-in blanks, and the answer key or mark scheme on its own page. Header and page numbers on every page. |
| `engine.py` | `build_prompt()`, `parse_spec()` (tolerates code fences and unescaped LaTeX backslashes), `spec_from_markdown()` (a reply that came back as headings and bullets), `spec_from_material()` (no AI), and `run()`. |

The AI only writes content; the design is fixed, so a revision sheet looks like a revision sheet whichever model wrote it.

**Maths** in `$...$`, and every formula block, is drawn with matplotlib's mathtext in Computer Modern (the textbook look chat got in 1.0.16) and placed inline. LaTeX mathtext can't parse falls back to readable text (Greek letters, superscripts), never raw source.

**Fonts:** DejaVu Sans from inside matplotlib, so Greek letters, arrows and ≤ ≥ print on any server.

**Without AI** (the free local model isn't installed): the material is laid out in the same template, as paragraphs under its headings; flashcards split at the first sentence; the practice exam and worksheet are cloze questions (the longest word blanked out). The cover says it was compiled without AI.

## JSON shape

Input: `{"spec": {...}, "doc_type": "revision_notes", "output_path": "out.pdf"}` or `{"material": ["<chunk>", ...], "doc_type": "study_guide", "title": "...", "output_path": "out.pdf"}`
Output: `{"document": "<path to pdf>", "doc_type": "..."}`

## Adding a type

Add it to `TEMPLATES`, to `_DOC_TYPES` in server/domains/knowledge/router.py, to `_docTypes` in the app's project_workspace_screen.dart, and (for chat) a pattern in the moderator's `_DOC_TYPE_REQUESTS`.

## Tests

`server/tests/test_document_templates.py` renders every template and reads each PDF back with PyMuPDF (title, kicker, answer page, `<`/`&` escaped, no LaTeX source left). `test_ai_generation.py` covers Studio writing from the material with a focus.
