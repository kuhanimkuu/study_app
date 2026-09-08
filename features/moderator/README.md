# Moderator (orchestrator)

> Status: ✅ core v1 — rule-based routing (now reaching essentially every engine in the project) + real local-LLM-authored prose for math routes

- **Input:** classified request (from an input engine, or `input_type: "project"` directly)
- **Output:** assembled response blocks

## Responsibilities

1. Understand intent ("what are they asking?")
2. Decide the response format (respect user request OR reason the best format)
3. Pick the engine(s) — the "tools" (carpenter analogy)
4. **Author the explanation prose** (the engines only produce facts)
5. Assemble facts + its own prose → blocks

## State

- **Pending context** — short-term: "what did I just ask the user?" (clarification loop), in-memory, keyed by `session_id`.
- **Activity log — local-first, not server state.** This module no longer writes to a server-side SQLite log itself (that used to be `personalization/memory_log`, called via `_log_event` after every resolved request). Instead every response includes a suggested `"activity"` dict (`{event, topic, engine, labels}`) for the *client* to persist to its own on-device store — see `server/README.md`'s "Architecture note: local-first data" and `frontend/lib/core/storage/local_db.dart`. `memory_query` (below) then answers over whatever activity events the client submits per-request as `local_events`, not a server-side table.

See `PATHWAY.md` §0 and `json.md` for the full pipeline and shapes.

## JSON shape

Input:
```json
{
    "input_type": "text",
    "content": "2x + 3 = 7",
    "task": null,
    "requested_format": null,
    "detected": ["math"],
    "query": null,
    "pdf_path": null,
    "project": null,
    "params": {},
    "session_id": "abc123"
}
```
Only `input_type` and `content` are required. `input_type` is one of `text | image | pdf | project`. `project` names a `rag/projects` slug (used when `input_type: "project"`). `params` carries structured arguments for engines that need more than free text can reliably supply (see "Structured (explicit-task-only) routes" below). Two more local-first fields (both optional, both client-supplied, neither ever persisted server-side — see the State section below): `model_config` (`{backend, tier, api_key?, model_name?}`, resolved server-side in `routers/ask.py` from the client's BYOK settings) and `local_events` (the client's own on-device activity log, used by `memory_query`).

Output:
```json
{ "blocks": [ {"type": "text", "content": "Solving 2x + 3 = 7: ...", "source": "moderator"}, {"type": "equation", "latex": "x = 2", "source": "symbolic"} ], "session_id": "abc123", "activity": {"event": "solve", "topic": "2x + 3 = 7", "engine": "symbolic", "labels": ["text", "solve"]} }
```
`activity` is a *suggestion* for the client to persist locally, not something this module writes anywhere itself — omitted when the request only produced a `clarification`.

## What this routes to (essentially the whole backend now)

**Text-triggerable** (free-text keyword/pattern matching, no explicit `task` needed):
| Trigger | Task | Engine(s) |
|---|---|---|
| contains `=` | `solve` | `math_engine/symbolic` |
| "differentiate"/"derivative" | `differentiate` | `math_engine/symbolic` |
| "integrate"/"integral" | `integrate` | `math_engine/symbolic` |
| "graph"/"plot"/"chart" | `graph` | `math_engine/graphing` |
| "interactive" + graph word | `interactive_2d` | `visual_explanation/interactive_2d` |
| "image of"/"picture of"/"draw" | `static_image` (PNG) | `math_engine/graphing` + `visual_explanation/static_images` |
| mentions "pdf" (takes priority over graph/interactive_2d/static_image) | `static_image` (PDF) | same engines, `format="pdf"` — a real vector PDF, emitted as a `"pdf"` block |
| "convert X UNIT to UNIT" | `unit_convert` | `math_engine/unit_conversion` |
| "what did I struggle"/"quiz me"/"my history" | `memory_query` | `personalization/query_memory` |
| `detected` contains `"math"` (no other match) | `simplify` | `math_engine/symbolic` |
| nothing else matches | *(research/conversation fallback)* | `research_engine/intent_analysis` → `research_engine/search_pipeline` if it needs current info; otherwise answered directly by `model_router` as general conversation (`_author_general_reply`) — a `clarification` is now only the last resort if that LLM call itself fails |

**Structured, explicit-task-only** (need real parameters free text can't reliably carry — pass `task` + `params` matching the target engine's own input contract directly):
`numeric_integrate` / `numeric_differentiate` / `numeric_root` / `numeric_stats` / `numeric_probability` (→ `math_engine/numeric`), `generate_doc` (→ `document_generation/generate_docs`), `diagram` (→ `visual_explanation/diagrams`), `animation` (→ `visual_explanation/animations`), `interactive_3d` (→ `visual_explanation/interactive_3d`), `simulation` (→ `visual_explanation/simulations`).

**`input_type: "image"`** — full pipeline, not just OCR: `image_processing/quality_analysis` → `image_processing/enhancement` → `image_processing/content_identification` (real vision routing, heuristic — see that engine's own honesty caveats) → whichever of `ocr/text_ocr`, `ocr/handwriting`, `ocr/math_ocr`, `ocr/table_extraction`, `ocr/graph_extraction`, `ocr/diagram_understanding`, `ocr/image_understanding` matches the detected content type.

**`input_type: "pdf"`** — `document_engine/pdf_processing` (via `input_pipeline/pdf_input`) for text, `document_engine/scanned_ocr` as an automatic fallback when that comes back empty (likely a scanned PDF), `document_engine/searchable_knowledge` for a query.

**`input_type: "project"`** — `input_pipeline/project_material` + `rag/projects`' stored index + `rag/semantic_search`, mirroring the PDF flow's upload → clarification → query shape.

**Not reachable from here:** `voice/*` (deliberately client-native, see that folder's READMEs), `model_router` (used internally for prose, not user-routable), and the handful of engines only ever called *by* other engines (`rag/indexing`, `document_engine/pdf_processing` when called via `pdf_input`, etc.).

## Notes

- **Routing is still genuinely rule-based, not an LLM in disguise** — regex/keyword matching (`_infer_task`) picks the task, same as before this expansion; only the *prose* is LLM-authored (see below). Deciding routes/picking engines doesn't need language ability by this project's own division of labour, so it's intentionally still deterministic — a real architectural choice, not a shortcut.
- **Phase 5 milestone: "authored prose" is a real local LLM call for the math routes**, not a template. `solve`/`simplify`/`differentiate`/`integrate`/`matrix_det`/`matrix_inverse` build their "text" block via `_author_text`, prompting `model_router` (tier `"tiny"`, real local `Qwen2.5-0.5B-Instruct` on CPU) with the computed facts, falling back to the fixed-template version (`_author_symbolic_text`) if the model call fails. Verified with a genuinely non-trivial example: asked to simplify `x**2 + 2*x + 1`, sympy's `simplify` alone left it unchanged, but the LLM's explanation correctly pointed out it factors to `(x + 1)^2`. Every other route (graph, image pipeline, PDF/project search, unit conversion, memory query, research, all structured tasks) still builds "text" from fixed templates or pass-through content — a deliberate, documented scope boundary.
- **Real, working clarification loop**, used by `pdf` (no query yet, or no `pdf_path`) and `project` (no project, or no query) routes — returns a `clarification` block and stores `{asked, context}` in an in-memory `_pending` dict keyed by `session_id` (`json.md` §7a). The next call with the same `session_id` and no explicit `task` resumes it — verified end-to-end for both input types.
- **General-conversation fallback (added after real-device testing surfaced the gap): free text that doesn't match anything else no longer just asks the user to clarify.** Previously `_route_research_or_clarify` had exactly two outcomes — a live web search, or a canned "I'm not sure what you'd like me to do" clarification — which meant a plain question like "explain the theory of relativity" got stonewalled instead of answered, even though the local/BYOK LLM was already wired in and perfectly capable of just answering it (same `model_router` call `_author_text` already uses for math prose). Now it's a three-step fallback: live search if genuinely needed → a direct LLM-authored conversational reply (`_author_general_reply`) → clarification only if that LLM call itself fails. This is a deliberate behavior change, not a bug: a bare, signal-less math expression like `x**2 + 2*x + 1` (no `=`, no operator keyword) now gets a genuine explanation instead of being asked "solve, graph, or simplify?" — see the `__main__` demo's "ambiguous math, no signal" case. The clarification loop itself is still real and still used, just no longer for this particular trigger; PDF/project flows exercise it exactly as before.
- **Real bug found and fixed alongside this**: `research_engine/intent_analysis`'s recency regex included bare `today`/`now`, so ordinary conversational phrasing like "hey how are you doing today" was misclassified as needing a live web search instead of getting a normal conversational reply. Fixed by dropping those two words from the regex — see `intent_analysis/README.md`.
- **Local-first activity log (pivoted from a server-side SQLite log)** — this module used to call `personalization/memory_log` directly after every resolved request; it now just returns a suggested `"activity"` dict in the response for the client to persist itself, and `personalization/query_memory` accepts the client's submitted `events` directly (`db_path`/`user_id` mode is kept only for standalone/admin use — see that engine's own module docstring). Verified end-to-end: a `local_events` list submitted on `/api/ask/text` with `task: "memory_query"` correctly filters by date range and struggle labels through the real HTTP endpoint, not just in a direct Python call.
- **New block types this expansion introduces** (beyond json.md's original list, following its own "shapes are proposed, not final" principle): `static_image`, `animation`, `3d` (already in json.md's vocab, just not previously emitted by anything). `table` and `diagram` were already in json.md's vocab and are now genuinely emitted (image pipeline / structured `diagram` task respectively). **The Flutter frontend doesn't have widgets for `static_image`, `animation`, or `3d` yet** — they fall back to `frontend`'s `UnknownBlockView`, an honest "not rendered yet" rather than a silent drop. `diagram`'s shape here (`{kind, elements: [{id,label,x,y}], relationships}`) matches `visual_explanation/diagrams`' own output but **differs from `ocr/diagram_understanding`'s shape** (`{kind, elements: [string, ...], relationships: []}` — a flat string list, not positioned nodes) — the image-pipeline route deliberately renders `ocr/diagram_understanding`'s result as a plain `text` description instead of forcing it into the `diagram` block type it doesn't actually match.
- Errors from any engine call are caught and turned into `{"type": "error", "engine": ..., "message": ...}` blocks (`json.md` Shape 4b) rather than crashing the whole response.
- **Known gap: "struggle" detection is a manual self-report, not real inference.** Neither this module nor any engine derives a genuine "the user is struggling with X" signal — there's no quiz/auto-grading engine in this project that would produce a score from an answer. The client currently plugs this gap with a "still stuck on this?" button on chat responses (`frontend/lib/features/chat/presentation/screens/chat_screen.dart`'s `_markStillStuck`) that writes a `struggle`-labelled activity event directly, bypassing this module entirely. The real fix — the moderator recognizing struggle from an actual back-and-forth (repeated clarifications, rephrased questions, follow-ups circling the same topic) across a session — is not implemented.
- **Known contract gap, still not fully resolved:** `document_engine/scanned_ocr`'s automatic fallback (when a PDF has no text layer) gives the user *some* OCR'd text to look at, but `document_engine/searchable_knowledge` (used for the actual query) still calls `pdf_processing` internally, not `scanned_ocr` — so search over a genuinely scanned PDF will likely come back empty even though the informational OCR pass worked. Said explicitly in the clarification message rather than silently failing later.
- `_extract_expression`/`_STRIP_KEYWORDS_RE` strip a growing list of leading filler words (`"graph"`, `"solve"`, `"what is"`, `"show"`, `"an interactive"`, `"image of"`, etc.) — still a crude regex stand-in for real language understanding, not NLU.
- **Real bugs found and fixed during this session's testing, not caught by earlier passes:**
  1. The PDF clarification's stored context never included `pdf_path` — a real follow-up API call (upload → clarification → reply with just a query) would have silently lost the file path. Fixed.
  2. Spoken-math words (`"plus"`, `"equals"`) from `audio_input`'s Whisper transcriptions weren't recognized as math at all. Fixed with `_normalize_spoken_operators`.
  3. `"show an interactive graph of sin(x)"` failed with `Cannot convert expression to float` — `_STRIP_KEYWORDS_RE` didn't know `"show"`/`"an"`/`"interactive"` as filler words, so the whole sentence got handed to sympy as if it were the expression. Fixed by extending the strip regex.
  4. `"graph y=3x + 2"` failed with a raw `invalid syntax` — sympy's `parse_expr` has no notion of `"="` at all. Fixed in `math_engine/graphing/engine.py` (strips a leading `"y ="`/`"f(x) ="` label before parsing).
  5. **Found via a real device test session, then a follow-up crash/edge-case audit**: `_extract_expression` only stripped a *leading* trigger phrase, so any trailing commentary after a legit expression ("y=3x + 2, and also generate its pdf for download") got handed to the parser verbatim and broke — affecting every text-triggered math route (solve/simplify/differentiate/integrate/graph/interactive_2d/static_image), not just graphing. Fixed with `_TRAILING_COMMENTARY_RE`.
  6. `_infer_task`'s bare `"=" in content` check misread ordinary chat emoticons as equations — `"thanks for the help =)"` crashed the parser, and worse, `"ok cool =D that makes sense"` silently parsed as a nonsense multi-symbol equation and got confidently "solved" and explained as if it were real math. Fixed by requiring a digit or arithmetic operator to co-occur with the `"="` (`_EQUATION_SIGNAL_RE`).
  7. `_route_project`'s "no query yet" branch called `_project_material.run()` without the same exception-wrapping every other engine call in this file has — a corrupted/partially-written project JSON file would have propagated an uncaught exception as a raw 500 instead of a clean error block. Fixed; verified with a real malformed JSON file.
  8. **Built while adding PDF export**: `"give me a pdf of the graph of x**2"` left `"a pdf of the graph of x**2"` as the extracted expression — no recognized trigger word fires until *after* "pdf", which `_extract_expression`'s single-pass strip didn't know how to look past, and sympy's implicit-multiplication parsing turned the leftover words into bogus free symbols instead of erroring cleanly (`Cannot convert expression to float`, not even an honest syntax error). Fixed by looping the leading-strip (`_LEADING_ARTICLE_RE` + `_STRIP_KEYWORDS_RE`) until stable instead of a single pass, plus a dedicated `_PDF_MODIFIER_RE` to remove the "pdf" phrase itself before extraction. Also found: the initial PDF-trigger condition required "graph"/"image"/"draw" to co-occur with "pdf", so `"generate a pdf of sin(x)"` (no such word) fell through to the general-conversation LLM fallback, which could only honestly say it couldn't produce a file. Loosened to trigger on any "pdf" mention alone.
- Tested standalone (`python engine.py`) and via direct calls covering every route added in this expansion: unit conversion, interactive 2D graphing, static image generation, a real live web search fallback (genuinely current results, e.g. MIT News/ScienceDaily quantum computing articles), memory query, the full image pipeline against a real text-bearing image, the project route end-to-end (create via `rag/projects` → query via the moderator), and all five structured tasks (`numeric_stats` matched exact values verified earlier for `math_engine/numeric`; `simulation` matched exact projectile-motion values verified earlier for `visual_explanation/simulations`, plus a bonus: it auto-builds an `interactive_graph` trajectory plot from the simulation's state data).
