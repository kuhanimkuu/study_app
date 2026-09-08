# Document generation / PDF output

> Status: ✅ wired up — reachable via `server/routers/projects.py`'s `/api/projects/{slug}/studio` endpoint (the Studio tab), which feeds it a project's own stored material chunks (also still callable directly by the moderator's structured `generate_doc` task for non-project use)

- **Input:** material
- **Output:** revision notes, formula sheets, study guides, lab reports, summaries, practice exams, flashcard PDFs, worksheets

## JSON shape

Input: `{ "material": ["<chunk 1>", "<chunk 2>"], "doc_type": "study_guide", "title": "My Study Guide", "output_path": "output.pdf" }` (`title`/`output_path` optional)
Output: `{ "document": "<path to generated pdf file>", "doc_type": "study_guide" }`

## Notes

Built on `reportlab` — produces a **real PDF file**, not a placeholder reference.

**Honesty note on `doc_type` handling** — there's no LLM in this phase to write real quiz questions or classify material into report sections:
- `study_guide` / `revision_notes` / `summary` / `formula_sheet` / `worksheet` (and any unrecognized `doc_type`) compile the material chunks into a titled document, one bullet per chunk — real, if simple.
- `flashcards` splits each chunk into front/back using a crude sentence heuristic (front = first sentence, back = the rest) — real work, not semantic Q&A generation.
- `practice_exam` generates real **cloze-deletion** questions (blanks out the longest word in each chunk, answer = the removed word) — a genuine, well-known simple quiz technique, not fabricated understanding.
- `lab_report` compiles chunks under generic section headers (Objective / Notes / Discussion) since there's no way to classify which chunk belongs where without real content understanding — all material lands under "Notes", with Objective/Discussion left as manual-fill placeholders.

Tested and verified for real (not just "file exists"): generated `study_guide`, `flashcards`, and `practice_exam` PDFs, then **read the `practice_exam` PDF back** through `document_engine/pdf_processing` to confirm actual content — correctly produced 3 cloze questions (e.g. `"Entropy is a measure of disorder in a _____ system."`) with a matching answer key (`"thermodynamic"`, `"thermodynamics"`, `"spontaneously"`).

**Studio wiring verified over real HTTP too:** generated a `study_guide` and `flashcards` PDF for a project via `/api/projects/{slug}/studio`, fetched the file back and confirmed real `%PDF` magic bytes (1.7KB, not an empty stub), listed both artifacts, deleted one and confirmed both its DB row and its file on disk were gone (a second fetch 404'd), and confirmed a project with no material yet is rejected with a clear 400 rather than generating an empty document.
