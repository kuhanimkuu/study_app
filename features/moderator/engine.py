"""
Moderator — the "real brain" / chef. Understands intent, decides the output
format, picks the engines (tools), authors the explanation prose, assembles
the blocks, and manages state (pending context + memory log).

INPUT (JSON) — what the moderator receives:
{
    "input_type": "text",          // text | image | pdf  (from an input_pipeline engine's output)
    "content": "2x + 3 = 7",       // for pdf, this is pdf_input's EXTRACTED TEXT, not a path (see Notes)
    "task": "solve",               // optional explicit task; inferred with rules if omitted
    "requested_format": null,      // optional: "graph" | "equation" | "steps" ...
    "detected": ["math"],          // optional, e.g. from text_input's output
    "query": "explain entropy",    // optional, only meaningful when input_type == "pdf"
    "pdf_path": "notes.pdf",       // optional, only needed when input_type == "pdf" AND query is set (see Notes)
    "session_id": "abc123"         // optional, default "default" — needed for the clarification loop to resume
}

OUTPUT (JSON) — what the moderator returns (the response):
{
    "blocks": [
        {"type": "text",     "content": "Solving 2x + 3 = 7 ...", "source": "moderator"},
        {"type": "equation", "latex": "x = 2",                     "source": "math_engine"}
    ],
    "session_id": "abc123"
}

Status: core v1 (rule-based; this is the stub Phase 5's LLM eventually replaces)
Composes sibling engines by loading their engine.py files directly via
importlib (feature folders don't import each other as packages yet, see
features/README.md) — same pattern used by document_engine/searchable_knowledge
and input_pipeline/pdf_input.

Phase 5 update: math routes (solve/simplify/differentiate/integrate/matrix)
now author their "text" block via a real local LLM (model_router, tier
"tiny" — see that engine's README for why transformers+PyTorch rather than
llama.cpp) given the engine's raw facts as context, with a graceful
fallback to the original f-string templates (`_author_symbolic_text`) if
the model call fails for any reason (not downloaded, out of memory, etc.)
— PATHWAY.md's stub table ("Explanation prose: Hardcoded templates ->
Moderator-authored (Phase 5)") is now genuinely satisfied for those routes,
not just aspirational. The pdf-search and image-OCR routes still build
their "text" blocks from fixed templates / pass-through content — not
upgraded in this pass, a deliberate scope boundary (this project's own
division of labour specifically flags *authoring the explanation* as
needing real language ability; deciding routes/picking engines does not,
so that rule-based logic is intentionally left as-is).

Known contract gap (discovered while building this, not papered over):
pdf_input's own output eagerly replaces "content" with the PDF's extracted
TEXT, but document_engine/searchable_knowledge needs the raw PDF PATH (it
re-opens and re-processes the file itself for chunking/embedding). Neither
this project's original skeletons nor json.md resolve that mismatch, so
this moderator accepts an explicit "pdf_path" input field to bridge it —
if input_type is "pdf" and "query" is set but "pdf_path" is missing, it
returns a clarification block explaining the gap rather than crashing.
"""
from __future__ import annotations

import importlib.util
import json
import re
import uuid
from pathlib import Path
from types import ModuleType
from typing import Any

_HERE = Path(__file__).resolve().parent
_FEATURES_ROOT = _HERE.parent  # features/

# Where generated artifacts (images, GIFs, GLB models, PDFs) get written so
# server/main.py can serve them back over HTTP — a bare local filesystem
# path in a block's "content" is useless to a Flutter client, which can
# only fetch a URL. server/main.py mounts this exact directory at the
# "/generated" URL prefix; block content for these types is the matching
# "/generated/<filename>" URL path, not a raw path, so the client can
# build a fetchable URL directly from base_url + content.
_GENERATED_DIR = _HERE / "generated"
_GENERATED_DIR.mkdir(exist_ok=True)


def _generated_file(extension: str) -> tuple[str, str]:
    """Returns (filesystem_path, url_path) for a new generated artifact."""
    filename = f"{uuid.uuid4().hex}.{extension}"
    return str(_GENERATED_DIR / filename), f"/generated/{filename}"


def _load_sibling_engine(relative_path: str) -> ModuleType:
    path = _FEATURES_ROOT / relative_path
    module_name = "moderator_dep_" + relative_path.replace("/", "_")
    spec = importlib.util.spec_from_file_location(module_name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_symbolic = _load_sibling_engine("math_engine/symbolic/engine.py")
_graphing = _load_sibling_engine("math_engine/graphing/engine.py")
_numeric = _load_sibling_engine("math_engine/numeric/engine.py")
_unit_conversion = _load_sibling_engine("math_engine/unit_conversion/engine.py")
_text_ocr = _load_sibling_engine("ocr/text_ocr/engine.py")
_handwriting = _load_sibling_engine("ocr/handwriting/engine.py")
_math_ocr = _load_sibling_engine("ocr/math_ocr/engine.py")
_table_extraction = _load_sibling_engine("ocr/table_extraction/engine.py")
_graph_extraction = _load_sibling_engine("ocr/graph_extraction/engine.py")
_diagram_understanding = _load_sibling_engine("ocr/diagram_understanding/engine.py")
_image_understanding = _load_sibling_engine("ocr/image_understanding/engine.py")
_quality_analysis = _load_sibling_engine("image_processing/quality_analysis/engine.py")
_enhancement = _load_sibling_engine("image_processing/enhancement/engine.py")
_content_identification = _load_sibling_engine("image_processing/content_identification/engine.py")
_pdf_processing = _load_sibling_engine("document_engine/pdf_processing/engine.py")
_scanned_ocr = _load_sibling_engine("document_engine/scanned_ocr/engine.py")
_searchable_knowledge = _load_sibling_engine("document_engine/searchable_knowledge/engine.py")
_generate_docs = _load_sibling_engine("document_generation/generate_docs/engine.py")
_rag_projects = _load_sibling_engine("rag/projects/engine.py")
_rag_semantic_search = _load_sibling_engine("rag/semantic_search/engine.py")
_project_material = _load_sibling_engine("input_pipeline/project_material/engine.py")
# personalization/memory_log is NOT loaded here — this server no longer
# writes activity data itself (local-first architecture, see run()'s
# "activity" field doc comment); that engine is still real, still tested,
# just not part of a live request's path anymore.
_query_memory = _load_sibling_engine("personalization/query_memory/engine.py")
_intent_analysis = _load_sibling_engine("research_engine/intent_analysis/engine.py")
_search_pipeline = _load_sibling_engine("research_engine/search_pipeline/engine.py")
_static_images = _load_sibling_engine("visual_explanation/static_images/engine.py")
_diagrams = _load_sibling_engine("visual_explanation/diagrams/engine.py")
_interactive_2d = _load_sibling_engine("visual_explanation/interactive_2d/engine.py")
_animations = _load_sibling_engine("visual_explanation/animations/engine.py")
_interactive_3d = _load_sibling_engine("visual_explanation/interactive_3d/engine.py")
_simulations = _load_sibling_engine("visual_explanation/simulations/engine.py")
_model_router = _load_sibling_engine("model_router/engine.py")


class NeedsClarification(Exception):
    def __init__(self, question: str, context: dict):
        super().__init__(question)
        self.question = question
        self.context = context


# --- state (per PATHWAY.md: _pending is the sanctioned short-term in-memory
# stub; long-term memory now goes through the real personalization/
# memory_log engine — see _log_event — not an in-memory stub anymore) ---

_pending: dict[str, dict] = {}

_GRAPH_RE = re.compile(r"\b(graph|plot|chart)\b", re.IGNORECASE)
_DIFF_RE = re.compile(r"\b(differentiate|derivative)\b", re.IGNORECASE)
_INTEGRATE_RE = re.compile(r"\b(integrate|integral)\b", re.IGNORECASE)
_UNIT_CONVERT_RE = re.compile(
    r"convert\s+([\d.]+)\s*([a-zA-Z°]+)\s+(?:to|into)\s+([a-zA-Z°]+)", re.IGNORECASE
)
_MEMORY_QUERY_RE = re.compile(
    r"\b(what did i struggle|quiz me|my (quiz )?history|how (have|did) i (been doing|done)|"
    r"weak (areas|topics))\b",
    re.IGNORECASE,
)
_INTERACTIVE_RE = re.compile(r"\binteractive\b", re.IGNORECASE)
_STATIC_IMAGE_RE = re.compile(r"\b(image of|picture of|draw)\b", re.IGNORECASE)
_PDF_EXPORT_RE = re.compile(r"\bpdf\b", re.IGNORECASE)
_STRIP_KEYWORDS_RE = re.compile(
    r"^\s*(what('?s| is)|calculate|compute|show( me)?|give me|generate)?\s*(an?\s+)?(interactive\s+)?"
    r"(graph|plot|chart|differentiate|derivative of|integrate|integral of|solve|simplify|image of|picture of|draw)?\s+(the\s+)?(of\s+)?",
    re.IGNORECASE,
)
# A leading article _STRIP_KEYWORDS_RE's own single pass can't reach when
# it's stranded in front of a trigger word rather than after one — e.g.
# "give me a pdf of THE graph of x**2" leaves "the graph of x**2" after
# _PDF_MODIFIER_RE removes "a pdf of ", and _STRIP_KEYWORDS_RE's `(the)?`
# slot only ever fires *after* a recognized trigger word, not before one.
# _extract_expression loops both of these together until stable instead
# of trying to enumerate every possible word order in one regex.
_LEADING_ARTICLE_RE = re.compile(r"^\s*(the|an?)\s+", re.IGNORECASE)
# Strips a "pdf" format request (see the PDF-export routing note above
# _route_static_image) out of the way before expression extraction — a
# real bug found while building that feature: "give me a pdf of the graph
# of x**2" left "a pdf of the graph of x**2" as the "expression" (no
# recognized trigger word fires until AFTER "pdf", which _STRIP_KEYWORDS_RE
# doesn't know about), and sympy's implicit-multiplication parsing turned
# the leftover words into bogus free symbols instead of erroring cleanly —
# "Cannot convert expression to float" when evaluated numerically.
_PDF_MODIFIER_RE = re.compile(r"\b(a\s+|the\s+)?pdf\b\s*(of|for)?\s*", re.IGNORECASE)
# Guards _infer_task's bare `"=" in content` equation check — without this,
# ordinary chat emoticons ("thanks =)", "ok cool =D") were misread as math
# (real bug, found via a crash/edge-case audit): "=)" alone crashed sympy's
# parser, and worse, some emoticon text ("ok cool =D that makes sense")
# silently parsed as a nonsense multi-symbol equation that got "solved" and
# confidently explained as if it were real math. Requiring a digit or an
# arithmetic operator to co-occur with the "=" is a narrow, honest fix —
# not full NLU — so a rare digit-free equation like "y = x" (no operator)
# won't be routed to solve; it still gets a reasonable answer via the
# general-conversation fallback instead, just not through the symbolic
# engine.
_EQUATION_SIGNAL_RE = re.compile(r"\d|[+\-*/^]")
# Trims trailing free-text commentary off an already-extracted expression —
# "y=3x + 2, and also generate its pdf for download" left the WHOLE
# trailing clause in the "expression" before this, breaking every
# text-triggered math route (solve/simplify/differentiate/integrate/graph/
# interactive_2d/static_image all share _extract_expression). Only trims
# from a recognizable conjunction boundary onward, same "gets the obvious
# cases right" honesty level as this file's other regexes — not real
# sentence-boundary detection.
_TRAILING_COMMENTARY_RE = re.compile(r"\s*,?\s+(and\s+(also|then)?|then|also)\b.*$", re.IGNORECASE)
_SPOKEN_OPERATORS_RE = [
    (re.compile(r"\bplus\b", re.IGNORECASE), "+"),
    (re.compile(r"\bminus\b", re.IGNORECASE), "-"),
    (re.compile(r"\btimes\b", re.IGNORECASE), "*"),
    (re.compile(r"\bdivided by\b", re.IGNORECASE), "/"),
    (re.compile(r"\bequals\b", re.IGNORECASE), "="),
]

# Explicit-task-only routes for engines needing structured parameters that
# can't be reliably extracted from free text (simulation parameters, a
# list of material chunks, diagram elements, etc.) — the caller must
# supply "params" matching the target engine's real input contract
# directly (e.g. {"task": "simulation", "params": {"domain": "physics",
# "type": "projectile", "parameters": {"velocity": 20, "angle": 45}}}).
# See moderator/README.md for the full list and why each isn't text-inferred.
_STRUCTURED_ENGINES: dict[str, tuple] = {
    "numeric_integrate": (_numeric, {"operation": "integrate"}),
    "numeric_differentiate": (_numeric, {"operation": "differentiate"}),
    "numeric_root": (_numeric, {"operation": "root"}),
    "numeric_stats": (_numeric, {"operation": "stats"}),
    "numeric_probability": (_numeric, {"operation": "probability"}),
    "generate_doc": (_generate_docs, {}),
    "diagram": (_diagrams, {}),
    "animation": (_animations, {}),
    "interactive_3d": (_interactive_3d, {}),
    "simulation": (_simulations, {}),
}


async def run(**kwargs: Any) -> dict:
    """Sole entry point the app calls.

    Args (kwargs): keys match INPUT above.
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    session_id: str = kwargs.get("session_id", "default")
    input_type: str = kwargs["input_type"]
    content: str = kwargs["content"]
    task: str | None = kwargs.get("task")
    requested_format: str | None = kwargs.get("requested_format")
    detected: list[str] = kwargs.get("detected", [])
    query: str | None = kwargs.get("query")
    pdf_path: str | None = kwargs.get("pdf_path")
    project: str | None = kwargs.get("project")
    params: dict = kwargs.get("params", {})
    # Per-user LLM preference (server/security.py's get_current_user ->
    # server/routers/ask.py builds this from the authenticated user's row —
    # see model_router/README.md for the shape). Defaults to the free local
    # model when the caller doesn't supply one (e.g. this file's own
    # __main__ demo, or any direct caller that hasn't opted into BYOK).
    model_config: dict = kwargs.get("model_config", {"backend": "local", "tier": "tiny"})
    user_id: int | None = kwargs.get("user_id")
    # Local-first architecture (see README.md's "Architecture note" and
    # moderator/README.md): the device, not this server, is the source of
    # truth for chat history/progress. local_events is the client's own
    # locally-stored activity log, submitted per-request — used only by
    # the memory_query route (below) to answer "what did I struggle with"
    # style questions; never persisted here.
    local_events: list[dict] = kwargs.get("local_events", [])

    if task is None and session_id in _pending:
        pending = _pending.pop(session_id)
        task = _task_from_clarification_reply(content)
        input_type = pending["context"]["input_type"]
        content = pending["context"]["content"]
        query = query or pending["context"].get("query")
        pdf_path = pdf_path or pending["context"].get("pdf_path")
        project = project or pending["context"].get("project")

    try:
        blocks, engine_used, topic = await _route(
            input_type, content, task, detected, query, pdf_path, requested_format, project, params,
            model_config, user_id, local_events,
        )
    except NeedsClarification as exc:
        _pending[session_id] = {"asked": exc.question, "context": exc.context}
        return {"blocks": [{"type": "clarification", "question": exc.question}], "session_id": session_id}

    # NOT persisted here — this project moved to a local-first model where
    # the DEVICE stores its own activity log (see README.md's "Architecture
    # note"). This "activity" field is a suggested entry for the client to
    # write to its own local storage; the server keeps no copy. Replaces
    # the earlier version, which called personalization/memory_log
    # (server-side SQLite) automatically on every request — that engine is
    # still real and correct, just no longer what a live request goes
    # through (see its own README for the server-side/admin use case it's
    # kept for).
    activity = {
        "event": task or "auto",
        "topic": topic,
        "engine": engine_used,
        "labels": [input_type] + ([task] if task else []) + list(detected),
    }
    return {"blocks": blocks, "session_id": session_id, "activity": activity}


# --- private helpers: decide_format() / pick_engines() / author_explanation() / assemble_blocks(), combined per route ---


async def _route(
    input_type: str,
    content: str,
    task: str | None,
    detected: list[str],
    query: str | None,
    pdf_path: str | None,
    requested_format: str | None,
    project: str | None,
    params: dict,
    model_config: dict,
    user_id: int | None,
    local_events: list[dict],
) -> tuple[list[dict], str, str]:
    if input_type == "pdf":
        return await _route_pdf(content, query, pdf_path)
    if input_type == "image":
        return await _route_image(content)
    if input_type == "project":
        return await _route_project(content, project, query, user_id)
    if input_type == "text":
        return await _route_text(content, task, detected, requested_format, params, model_config, user_id, local_events)
    raise NeedsClarification(f"I don't know how to handle input_type={input_type!r} yet.", {"input_type": input_type, "content": content})


async def _route_pdf(content: str, query: str | None, pdf_path: str | None) -> tuple[list[dict], str, str]:
    was_scanned = False
    if pdf_path and not content.strip():
        # pdf_input's own extraction came back empty — likely a scanned PDF
        # with no text layer. document_engine/scanned_ocr exists for exactly
        # this; run it so the user at least sees SOMETHING rather than a
        # silent empty document. Honesty limit: searchable_knowledge (used
        # below for the actual query) still calls pdf_processing internally,
        # not scanned_ocr — so full search over scanned PDFs isn't wired up,
        # only this informational OCR pass. Said explicitly in the message.
        try:
            scanned = await _scanned_ocr.run(pdf=pdf_path)
            ocr_text = "\n".join(scanned["text"].values())
        except Exception:
            ocr_text = ""
        if ocr_text.strip():
            content = ocr_text
            was_scanned = True

    if not query:
        note = (
            " (This looks like a scanned PDF — I ran OCR and got some text, but full search over "
            "scanned PDFs isn't wired up yet, so a search may come back empty.)"
            if was_scanned
            else ""
        )
        raise NeedsClarification(
            "I've read this PDF. What would you like me to do with it, for example search for a topic "
            f"or ask about specific pages?{note}",
            {"input_type": "pdf", "content": content, "pdf_path": pdf_path},
        )
    if not pdf_path:
        raise NeedsClarification(
            "I have your query but not the PDF's file path (searchable_knowledge needs to re-open the "
            "file itself). Please resend with 'pdf_path' set.",
            {"input_type": "pdf", "content": content, "query": query},
        )

    try:
        result = await _searchable_knowledge.run(pdf=pdf_path, query=query)
    except Exception as exc:
        return (
            [{"type": "error", "engine": "searchable_knowledge", "message": str(exc)}],
            "searchable_knowledge",
            query,
        )

    blocks = [
        {"type": "text", "content": f"Searched the PDF for '{query}'.", "source": "moderator"},
        {"type": "text", "content": result["answer"], "source": "searchable_knowledge"},
    ]
    for chunk in result["chunks"][:3]:
        blocks.append({"type": "source", "content": chunk, "source": "searchable_knowledge"})
    return blocks, "searchable_knowledge", query


_PROJECTS_ROOT = _FEATURES_ROOT / "rag" / "projects" / "projects"


def _user_projects_dir(user_id: int | None) -> Path:
    """Per-user namespacing for project storage — two different users
    naming a project the same slug (e.g. "thermodynamics") must not
    collide or see each other's material (routers/projects.py creates
    projects under this same scheme). Falls back to the shared root only
    when there's no authenticated user — shouldn't happen via the HTTP
    API, which requires auth on every /api/ask/* call; kept for this
    module's own __main__ demo / standalone testing."""
    if user_id is None:
        return _PROJECTS_ROOT
    return _PROJECTS_ROOT / f"user_{user_id}"


async def _route_project(
    content: str, project: str | None, query: str | None, user_id: int | None
) -> tuple[list[dict], str, str]:
    """Composes rag/projects' storage (read directly, same convention as
    input_pipeline/project_material) + rag/semantic_search — mirrors
    _route_pdf's shape (upload/select -> clarification -> query resolves
    it) for consistency.

    Deliberate scope boundary, same as several other routes: this returns
    the matching chunks as `source` blocks, not an LLM-synthesized answer
    over them — see moderator/README.md's Notes for why (no route beyond
    the math ones gets authored prose yet)."""
    if not project:
        raise NeedsClarification("Which project is this about?", {"input_type": "project", "content": content})

    projects_dir = _user_projects_dir(user_id)

    if not query:
        # Unlike every other engine call in this function (semantic_search
        # a few lines below, plus symbolic/graphing/unit_conversion
        # elsewhere in this file), this one wasn't exception-wrapped — a
        # corrupted/partially-written project JSON file would have
        # propagated an uncaught exception all the way up through
        # routers/ask.py as a raw 500 instead of the {"blocks": [...]}
        # shape the client expects. Found via a crash/edge-case audit.
        try:
            material = await _project_material.run(content=content, project=project, projects_dir=projects_dir)
        except Exception as exc:
            return [{"type": "error", "engine": "project_material", "message": str(exc)}], "project_material", project
        chunk_count = len(material["context"])
        raise NeedsClarification(
            f"I have your '{project}' project loaded ({chunk_count} stored chunk(s)). What would you like to know?",
            {"input_type": "project", "content": content, "project": project},
        )

    index = _load_project_index(project, projects_dir)
    if index is None or not index.get("chunks"):
        return (
            [{"type": "error", "engine": "rag_projects", "message": f"no stored material found for project {project!r}"}],
            "rag_projects",
            project,
        )

    try:
        search_result = await _rag_semantic_search.run(index=index, query=query, top_k=3)
    except Exception as exc:
        return [{"type": "error", "engine": "semantic_search", "message": str(exc)}], "semantic_search", query

    results = search_result["results"]
    if not results:
        return (
            [{"type": "text", "content": f"No relevant material found in '{project}' for '{query}'.", "source": "moderator"}],
            "semantic_search",
            query,
        )

    blocks = [{"type": "text", "content": f"Searched project '{project}' for '{query}'.", "source": "moderator"}]
    for r in results:
        blocks.append({"type": "source", "content": r["chunk"], "source": f"{project} (score {r['score']:.2f})"})
    return blocks, "semantic_search", query


def _load_project_index(project: str, projects_dir: Path) -> dict | None:
    project_file = projects_dir / f"{project}.json"
    if not project_file.exists():
        return None
    return json.loads(project_file.read_text(encoding="utf-8"))


_IMAGE_ROUTE_ENGINES = {
    "text": _text_ocr,
    "handwriting": _handwriting,
    "math": _math_ocr,
    "table": _table_extraction,
    "graph": _graph_extraction,
    "diagram": _diagram_understanding,
    "photo": _image_understanding,
}


async def _route_image(content: str) -> tuple[list[dict], str, str]:
    """Full pipeline matching the original architecture's intent for the
    image_processing category (PATHWAY.md / features.md): quality_analysis
    -> enhancement -> content_identification (real vision routing) -> the
    specific engine for whatever was actually detected. Replaces the
    earlier version, which always ran plain text_ocr regardless of what
    the image contained — content_identification's own README already
    flags it as a best-effort heuristic classifier, not a trained model,
    so this inherits that honesty limit."""
    try:
        quality = (await _quality_analysis.run(image=content))["quality"]
        enhanced = await _enhancement.run(image=content, quality=quality)
        image_path = enhanced["image"]
        applied = enhanced["applied"]
    except Exception:
        # preprocessing failure isn't fatal — fall back to the original
        # image rather than failing the whole request over it
        image_path = content
        applied = []

    try:
        routing = await _content_identification.run(image=image_path)
        route = routing["route"]
        route_confidence = routing["confidence"]
    except Exception as exc:
        return [{"type": "error", "engine": "content_identification", "message": str(exc)}], "content_identification", "image"

    engine = _IMAGE_ROUTE_ENGINES.get(route, _text_ocr)
    engine_name = route if route in _IMAGE_ROUTE_ENGINES else "text_ocr"
    try:
        result = await engine.run(image=image_path)
    except Exception as exc:
        return [{"type": "error", "engine": engine_name, "message": str(exc)}], engine_name, route

    intro = f"Detected this as {route} content (confidence {route_confidence:.0%})."
    if applied:
        intro += f" Image preprocessing applied: {', '.join(applied)}."
    blocks = [{"type": "text", "content": intro, "source": "moderator"}]
    blocks.extend(_image_result_to_blocks(route, result, engine_name))
    return blocks, engine_name, route


def _image_result_to_blocks(route: str, result: dict, engine_name: str) -> list[dict]:
    if route in ("text", "handwriting"):
        return [{"type": "text", "content": result["text"], "source": engine_name}]
    if route == "math":
        return [{"type": "equation", "latex": result["latex"], "source": engine_name}]
    if route == "table":
        table = result["table"]
        return [{"type": "table", "headers": table["headers"], "rows": table["rows"], "source": engine_name}]
    if route == "graph":
        return [{"type": "interactive_graph", "data": result["data"], "source": engine_name}]
    if route == "diagram":
        diagram = result["diagram"]
        description = f"Kind: {diagram['kind']}. Elements detected: {', '.join(diagram['elements']) or 'none'}."
        return [{"type": "text", "content": description, "source": engine_name}]
    if route == "photo":
        return [{"type": "text", "content": result["description"], "source": engine_name}]
    return [{"type": "text", "content": str(result), "source": engine_name}]


async def _route_text(
    content: str,
    task: str | None,
    detected: list[str],
    requested_format: str | None,
    params: dict,
    model_config: dict,
    user_id: int | None,
    local_events: list[dict],
) -> tuple[list[dict], str, str]:
    if task is None and requested_format in ("graph", "interactive_2d"):
        task = requested_format
    content = _normalize_spoken_operators(content)
    if task is None:
        task = _infer_task(content, detected)
    if task is None:
        return await _route_research_or_clarify(content, model_config)

    if task in _STRUCTURED_ENGINES:
        return await _route_structured(task, params)

    expression = _extract_expression(content)

    if task == "unit_convert":
        return await _route_unit_convert(content)
    if task == "memory_query":
        return await _route_memory_query(content, local_events)
    if task == "interactive_2d":
        return await _route_interactive_2d(expression, params)
    if task == "static_image":
        return await _route_static_image(expression, params, content)

    if task == "graph":
        try:
            result = await _graphing.run(expression=expression, range=[-10, 10])
        except Exception as exc:
            return [{"type": "error", "engine": "graphing", "message": str(exc)}], "graphing", expression
        blocks = [
            {"type": "text", "content": f"Here's the graph of {result['latex']}.", "source": "moderator"},
            {"type": "interactive_graph", "data": result["points"], "latex": result["latex"], "source": "graphing"},
        ]
        return blocks, "graphing", expression

    if task in ("solve", "simplify", "differentiate", "integrate", "matrix_det", "matrix_inverse"):
        operation = None if task == "solve" else task
        try:
            result = await _symbolic.run(expression=expression, operation=operation)
        except Exception as exc:
            return [{"type": "error", "engine": "symbolic", "message": str(exc)}], "symbolic", expression
        text = await _author_text(task, expression, result, model_config)
        blocks = [
            {"type": "text", "content": text, "source": "moderator"},
            {"type": "equation", "latex": result["latex"], "source": "symbolic"},
        ]
        return blocks, "symbolic", expression

    raise NeedsClarification(
        f"I understood you want '{task}', but I don't have an engine for that yet.",
        {"input_type": "text", "content": content},
    )


async def _route_research_or_clarify(content: str, model_config: dict) -> tuple[list[dict], str, str]:
    """Reached when no task could be inferred at all. Three-step fallback,
    each one honest about why it's tried before falling through:
      1. research_engine/intent_analysis — if this genuinely looks like it
         needs current/external information, run a real live web search
         (research_engine/search_pipeline) instead of guessing an answer.
      2. General conversation — doesn't need live search and isn't a
         structured task either, so this is answered directly by the LLM
         (model_router), the same real local/BYOK model already used to
         author math explanations elsewhere (see _author_text). This is
         what makes the app usable for plain "explain X" / conversational
         questions, not just a router over a fixed task list.
      3. Clarification — only reached if the LLM call itself fails (no
         BYOK key, local model unavailable, etc.); there's no template
         fallback for open-ended conversation the way _author_text has
         one for math, so this is the honest last resort."""
    try:
        intent = await _intent_analysis.run(query=content)
    except Exception:
        intent = {"needs_external": False}

    if intent.get("needs_external"):
        try:
            sources = (await _search_pipeline.run(query=content))["sources"]
        except Exception:
            sources = []
        if sources:
            blocks = [
                {
                    "type": "text",
                    "content": f"This looked like it needs current information, so I searched the web "
                    f"for '{content}'.",
                    "source": "moderator",
                },
            ]
            for source in sources[:5]:
                blocks.append(
                    {"type": "source", "content": f"{source['title']}: {source['snippet']}", "source": source["url"]}
                )
            return blocks, "search_pipeline", content

    general_reply = await _author_general_reply(content, model_config)
    if general_reply is not None:
        return [{"type": "text", "content": general_reply, "source": "moderator"}], "model_router", content

    raise NeedsClarification(
        "I'm not sure what you'd like me to do with this. Could you clarify, for example solve it, "
        "graph it, differentiate it, integrate it, convert a unit, or search for it?",
        {"input_type": "text", "content": content},
    )


async def _author_general_reply(content: str, model_config: dict) -> str | None:
    """General-conversation fallback used by _route_research_or_clarify.
    Unlike _author_text's math routes, there's no non-LLM template that
    could stand in for an open-ended conversational answer — so a failed
    call here returns None (not a canned reply), and the caller falls
    back to asking for clarification instead of faking an answer."""
    prompt = (
        "You are a helpful, knowledgeable study assistant having a normal conversation. "
        f"The student said: '{content}'. Reply naturally and concisely (2-4 sentences unless "
        "the question clearly needs more detail)."
    )
    try:
        llm_result = await _model_router.run(prompt=prompt, max_tokens=220, **model_config)
        text = llm_result["text"].strip()
        return text or None
    except Exception:
        return None


async def _route_unit_convert(content: str) -> tuple[list[dict], str, str]:
    match = _UNIT_CONVERT_RE.search(content)
    if not match:
        raise NeedsClarification(
            "What would you like to convert, and to what unit? (e.g. \"convert 100 km to miles\")",
            {"input_type": "text", "content": content},
        )
    value_str, from_unit, to_unit = match.groups()
    try:
        result = await _unit_conversion.run(value=float(value_str), from_unit=from_unit, to_unit=to_unit)
    except Exception as exc:
        return [{"type": "error", "engine": "unit_conversion", "message": str(exc)}], "unit_conversion", content
    text = f"{value_str} {from_unit} = {result['value']:.6g} {to_unit}"
    return [{"type": "text", "content": text, "source": "unit_conversion"}], "unit_conversion", content


async def _route_memory_query(content: str, local_events: list[dict]) -> tuple[list[dict], str, str]:
    """Local-first: filters the CLIENT'S own submitted activity log
    (local_events) — this server never stores or reads a memory log of its
    own for a live request anymore, see run()'s "activity" doc comment."""
    try:
        result = await _query_memory.run(query=content, events=local_events)
    except Exception as exc:
        return [{"type": "error", "engine": "query_memory", "message": str(exc)}], "query_memory", content

    events = result["events"]
    if not events:
        return (
            [{"type": "text", "content": "No matching activity found in your history yet.", "source": "moderator"}],
            "query_memory",
            content,
        )

    blocks = [
        {"type": "text", "content": f"Found {len(events)} matching activit{'y' if len(events) == 1 else 'ies'}:", "source": "moderator"}
    ]
    for event in events:
        score_str = f", score {event['score']:.2f}" if event.get("score") is not None else ""
        blocks.append(
            {
                "type": "source",
                "content": f"{event['topic']}{score_str} — labels: {', '.join(event['labels'])}",
                "source": "memory_log",
            }
        )
    return blocks, "query_memory", content


async def _route_interactive_2d(expression: str, params: dict) -> tuple[list[dict], str, str]:
    expr = params.get("expression", expression)
    value_range = params.get("range", [-10, 10])
    try:
        result = await _interactive_2d.run(expression=expr, range=value_range)
    except Exception as exc:
        return [{"type": "error", "engine": "interactive_2d", "message": str(exc)}], "interactive_2d", expr
    points = result["visual"]["data"]["points"]
    blocks = [
        {"type": "text", "content": f"Here's an interactive graph of {expr}.", "source": "moderator"},
        {"type": "interactive_graph", "data": points, "source": "interactive_2d"},
    ]
    return blocks, "interactive_2d", expr


async def _route_static_image(expression: str, params: dict, content: str) -> tuple[list[dict], str, str]:
    """PNG by default; a real PDF (matplotlib's Agg backend saves vector
    PDF natively, not a converted raster — see static_images/engine.py)
    when the request mentions "pdf" (see _PDF_EXPORT_RE / _infer_task's
    routing note above). The PDF case emits a `"pdf"` block, not
    `"static_image"` — reusing the same block type/shape
    document_generation/generate_docs already produces, so the Flutter
    client's existing PdfBlockView renders it with no new widget needed."""
    expr = params.get("expression", expression)
    value_range = params.get("range", [-10, 10])
    image_format = "pdf" if _PDF_EXPORT_RE.search(content) else params.get("format", "png")
    fs_path, url_path = _generated_file(image_format)
    try:
        graph_result = await _graphing.run(expression=expr, range=value_range)
        image_result = await _static_images.run(
            data={"points": graph_result["points"], "title": graph_result["latex"]},
            format=image_format,
            output_path=fs_path,
        )
    except Exception as exc:
        return [{"type": "error", "engine": "static_images", "message": str(exc)}], "static_images", expr

    if image_format == "pdf":
        blocks = [
            {"type": "text", "content": f"Here's a downloadable PDF of {graph_result['latex']}.", "source": "moderator"},
            {"type": "pdf", "content": url_path, "doc_type": "graph", "source": "static_images"},
        ]
    else:
        blocks = [
            {"type": "text", "content": f"Here's an image of {graph_result['latex']}.", "source": "moderator"},
            {"type": "static_image", "content": url_path, "format": image_result["format"], "source": "static_images"},
        ]
    return blocks, "static_images", expr


# task -> file extension, for tasks whose result is a file the client needs
# a fetchable URL for (see _GENERATED_DIR's doc comment)
_FILE_PRODUCING_TASKS = {"generate_doc": "pdf", "animation": "gif", "interactive_3d": "glb"}


async def _route_structured(task: str, params: dict) -> tuple[list[dict], str, str]:
    engine, extra_kwargs = _STRUCTURED_ENGINES[task]
    call_kwargs = {**extra_kwargs, **params}

    url_path = None
    if task in _FILE_PRODUCING_TASKS and "output_path" not in call_kwargs:
        fs_path, url_path = _generated_file(_FILE_PRODUCING_TASKS[task])
        call_kwargs["output_path"] = fs_path

    try:
        result = await engine.run(**call_kwargs)
    except Exception as exc:
        return [{"type": "error", "engine": task, "message": str(exc)}], task, task
    blocks = _structured_result_to_blocks(task, result, url_path)
    topic = str(params.get("expression") or params.get("domain") or params.get("doc_type") or task)[:80]
    return blocks, task, topic


def _structured_result_to_blocks(task: str, result: dict, url_path: str | None) -> list[dict]:
    if task.startswith("numeric_"):
        blocks = [{"type": "text", "content": f"Result: {result['answer']}", "source": "moderator"}]
        latex = result.get("latex")
        if latex:
            blocks.append({"type": "equation", "latex": latex, "source": "numeric"})
        return blocks
    if task == "generate_doc":
        return [
            {"type": "pdf", "content": url_path or result["document"], "doc_type": result["doc_type"], "source": "generate_docs"}
        ]
    if task == "diagram":
        d = result["diagram"]
        return [
            {
                "type": "diagram",
                "kind": d["kind"],
                "elements": d["elements"],
                "relationships": d["relationships"],
                "source": "diagrams",
            }
        ]
    if task == "animation":
        anim = result["animation"]
        return [{"type": "animation", "content": url_path or anim["file"], "fps": anim["fps"], "source": "animations"}]
    if task == "interactive_3d":
        return [{"type": "3d", "content": url_path or result["model"], "format": result["format"], "source": "interactive_3d"}]
    if task == "simulation":
        sim = result["simulation"]
        blocks = [{"type": "text", "content": f"Simulation ({sim['domain']}): {sim.get('summary')}", "source": "moderator"}]
        state = sim.get("state", {})
        if "x" in state and "y" in state:
            blocks.append({"type": "interactive_graph", "data": {"x": state["x"], "y": state["y"]}, "source": "simulations"})
        return blocks
    return [{"type": "text", "content": str(result), "source": task}]


def _infer_task(content: str, detected: list[str]) -> str | None:
    if _UNIT_CONVERT_RE.search(content):
        return "unit_convert"
    if _MEMORY_QUERY_RE.search(content):
        return "memory_query"
    # An explicit "...pdf..." request takes priority over the plain
    # graph/interactive_2d routes — those only ever return interactive
    # point data or a PNG, never a downloadable file, so "graph y=3x+2
    # as a pdf" needs to land on static_image (which _route_static_image
    # then renders as an actual PDF, not just an image) rather than the
    # data-only interactive_2d/graph routes silently swallowing "pdf".
    # Deliberately not requiring _GRAPH_RE/_STATIC_IMAGE_RE too — "generate
    # a pdf of sin(x)" (no "graph"/"image"/"draw" word at all) is a real,
    # natural phrasing that would otherwise fall through to the general-
    # conversation LLM fallback, which can only honestly admit it can't
    # produce a file (found via live testing, not theoretical).
    if _PDF_EXPORT_RE.search(content):
        return "static_image"
    if _INTERACTIVE_RE.search(content) and _GRAPH_RE.search(content):
        return "interactive_2d"
    if _GRAPH_RE.search(content):
        return "graph"
    if _STATIC_IMAGE_RE.search(content):
        return "static_image"
    if _DIFF_RE.search(content):
        return "differentiate"
    if _INTEGRATE_RE.search(content):
        return "integrate"
    if "=" in content and _EQUATION_SIGNAL_RE.search(content):
        return "solve"
    if "math" in detected:
        return "simplify"
    return None


def _normalize_spoken_operators(content: str) -> str:
    """Converts spelled-out operators ("2 plus 3") to symbols ("2 + 3") —
    added specifically because input_pipeline/audio_input's transcriptions
    are spoken language, not typed math notation, and neither _infer_task's
    "=" check nor _extract_expression's sympy parsing understood the words.
    Found and fixed by testing the audio_input -> moderator path end to end
    through the HTTP server."""
    for pattern, symbol in _SPOKEN_OPERATORS_RE:
        content = pattern.sub(f" {symbol} ", content)
    return content


def _extract_expression(content: str) -> str:
    stripped = _PDF_MODIFIER_RE.sub(" ", content).strip()
    while True:
        before = stripped
        stripped = _LEADING_ARTICLE_RE.sub("", stripped).strip()
        stripped = _STRIP_KEYWORDS_RE.sub("", stripped).strip()
        if stripped == before:
            break
    stripped = _TRAILING_COMMENTARY_RE.sub("", stripped).strip()
    return stripped.rstrip("?.")


def _task_from_clarification_reply(reply: str) -> str | None:
    reply = reply.strip().lower()
    for keyword, task in (
        ("interactive", "interactive_2d"),
        ("graph", "graph"), ("plot", "graph"),
        ("image of", "static_image"), ("picture of", "static_image"),
        ("differentiate", "differentiate"), ("derivative", "differentiate"),
        ("integrate", "integrate"), ("integral", "integrate"),
        ("convert", "unit_convert"),
        ("struggle", "memory_query"), ("quiz me", "memory_query"),
        ("solve", "solve"), ("simplify", "simplify"),
        ("search", None),  # handled via query, not task, for pdf/project replies
    ):
        if keyword in reply:
            return task
    return None


async def _author_text(task: str, expression: str, result: dict, model_config: dict) -> str:
    """Real LLM-authored explanation, given the engine's raw facts as
    context — falls back to the fixed-template version if the model call
    fails for any reason (wrong/expired BYOK key, local model not
    downloaded, network error for a hosted backend, etc.). This is the
    actual Phase 5 "authors the explanation" capability, not aspirational.

    `model_config` is the caller's chosen backend (per-user for BYOK —
    see model_router/README.md): {"backend": "local"|"anthropic"|"openai",
    "tier"?: str, "api_key"?: str, "model_name"?: str}."""
    prompt = (
        "You are a concise, clear math tutor. A student asked to "
        f"{task} the expression '{expression}'. The computed result is: "
        f"answer = {result['answer']}, steps = {result['steps']}. "
        "In 1-2 short sentences, explain this result to the student. "
        "Do not repeat the raw steps list verbatim; explain it naturally."
    )
    try:
        llm_result = await _model_router.run(prompt=prompt, max_tokens=120, **model_config)
        text = llm_result["text"].strip()
        if text:
            return text
    except Exception:
        pass
    return _author_symbolic_text(task, expression, result)


def _author_symbolic_text(task: str, expression: str, result: dict) -> str:
    """Templated, not authored — the fallback _author_text() uses if the
    real LLM call fails for any reason."""
    if task == "solve":
        steps = " ".join(result["steps"])
        return f"Solving {expression}: {steps} Answer: {result['answer']}."
    if task == "simplify":
        return f"Simplifying {expression} gives {result['answer']}."
    if task == "differentiate":
        return f"The derivative of {expression} is {result['answer']}."
    if task == "integrate":
        return f"The integral of {expression} is {result['answer']}."
    if task == "matrix_det":
        return f"The determinant of {expression} is {result['answer']}."
    if task == "matrix_inverse":
        return f"The inverse of {expression} is {result['answer']}."
    return str(result["answer"])


if __name__ == "__main__":
    import asyncio
    import sys

    def show(label: str, result: dict) -> None:
        enc = sys.stdout.encoding or "utf-8"
        print(f"--- {label} ---")
        for block in result["blocks"]:
            btype = block["type"]
            if btype == "text":
                text = block["content"][:150].encode(enc, errors="replace").decode(enc)
                print(f"  [text/{block['source']}] {text}")
            elif btype == "equation":
                print(f"  [equation/{block['source']}] {block['latex']}")
            elif btype == "interactive_graph":
                print(f"  [interactive_graph/{block['source']}] {len(block['data']['x'])} points")
            elif btype == "clarification":
                print(f"  [clarification] {block['question']}")
            elif btype == "error":
                print(f"  [error/{block['engine']}] {block['message']}")
            elif btype == "source":
                text = str(block["content"])[:100].encode(enc, errors="replace").decode(enc)
                print(f"  [source/{block['source']}] {text}")
            else:
                print(f"  [{btype}] {block}")

    async def demo() -> None:
        # --- previously verified routes (still working after the expansion) ---
        show("solve", await run(input_type="text", content="2x + 3 = 7", detected=["math"]))
        show("graph", await run(input_type="text", content="graph x**2"))
        show("differentiate", await run(input_type="text", content="differentiate x**3 + 2*x"))
        show(
            "ambiguous math, no signal (now genuinely answered by the general-conversation "
            "fallback instead of stonewalled with a clarification)",
            await run(input_type="text", content="x**2 + 2*x + 1", session_id="s1"),
        )
        show("follow-up conversational question, same session", await run(input_type="text", content="what about x**2 - 4?", session_id="s1"))
        show("pdf without query (expect clarification)", await run(input_type="pdf", content="some extracted text", session_id="s2"))

        # --- newly wired routes ---
        show("unit conversion", await run(input_type="text", content="convert 100 km to miles"))
        show("interactive 2d", await run(input_type="text", content="show an interactive graph of sin(x)"))
        show("static image", await run(input_type="text", content="image of x**2"))
        show("research fallback (needs live web + genuinely may vary)", await run(input_type="text", content="latest research on quantum computing"))
        show(
            "general conversation (no engine fits, no live-search need — answered directly by the LLM)",
            await run(input_type="text", content="tell me about entropy", session_id="s3"),
        )
        show(
            "memory query (local-first: filters CLIENT-submitted events, no server DB)",
            await run(
                input_type="text",
                content="what did I struggle with?",
                local_events=[
                    {"topic": "thermodynamics", "score": 0.4, "labels": ["struggle"], "timestamp": None},
                    {"topic": "algebra", "score": 0.95, "labels": ["quiz"], "timestamp": None},
                ],
            ),
        )
        show(
            "structured task: numeric integration (explicit task+params)",
            await run(input_type="text", content="", task="numeric_integrate", params={"expression": "sin(x)", "bounds": [0, 3.14159265]}),
        )

    asyncio.run(demo())
