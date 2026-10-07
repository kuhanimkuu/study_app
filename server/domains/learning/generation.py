"""
AI generation of study content from a Knowledge Space's own uploaded
material (2026-10-07) — concepts, flashcards, and practice questions.
Before this, all three were manual-entry only: uploading a PDF to a
project produced a search index and nothing study-ready.

Every function here returns plain data; the routers persist it. Model
output is parsed leniently (the free local model doesn't follow formats
reliably) but *validated strictly* before anything is saved — e.g. an MCQ
is only kept if its answer letter maps to one of its own options, so a
generated question can always be graded by grading.py.

Grounding: everything is generated from the project's indexed chunks (the
same index search and project Q&A use), never from the topic name alone —
concept-scoped generation pulls that concept's most relevant passages via
semantic search first.
"""
from __future__ import annotations

import re

from fastapi import HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from ... import engines
from ..billing import service as billing_service

# The free local model (~0.5B params) slows down sharply and loses the
# thread on long prompts; BYOK/hosted models handle far more.
_LOCAL_MATERIAL_CHARS = 3000
_REMOTE_MATERIAL_CHARS = 12000


def material_budget(model_config: dict) -> int:
    return _LOCAL_MATERIAL_CHARS if model_config.get("backend", "local") == "local" else _REMOTE_MATERIAL_CHARS


def load_chunks(user_id: int, slug: str) -> list[str]:
    projects_dir = engines.moderator._user_projects_dir(user_id)
    index = engines.moderator._load_project_index(slug, projects_dir)
    chunks = (index or {}).get("chunks") or []
    if not chunks:
        raise HTTPException(status_code=400, detail="this project has no material yet — add some in Sources first")
    return [str(c) for c in chunks]


def sample_material(chunks: list[str], budget: int) -> str:
    """Spread across the whole material rather than only its beginning —
    a 40-page PDF's first 3000 characters is usually the table of
    contents. Takes evenly spaced chunks until the budget is used."""
    total = sum(len(c) for c in chunks)
    if total <= budget:
        return "\n\n".join(chunks)
    avg = max(1, total // len(chunks))
    take = max(1, budget // avg)
    step = len(chunks) / take
    picked: list[str] = []
    used = 0
    for i in range(take):
        chunk = chunks[int(i * step)]
        if used + len(chunk) > budget and picked:
            break
        picked.append(chunk[: budget - used])
        used += len(picked[-1])
    return "\n\n".join(picked)


async def relevant_material(user_id: int, slug: str, query: str, budget: int) -> str:
    """The passages most relevant to `query` (a concept's name and
    description) — falls back to an even sample if search fails."""
    chunks = load_chunks(user_id, slug)
    projects_dir = engines.moderator._user_projects_dir(user_id)
    index = engines.moderator._load_project_index(slug, projects_dir)
    try:
        result = await engines.semantic_search.run(index=index, query=query, top_k=8)
        ranked = [r["chunk"] for r in result.get("results", []) if r.get("chunk")]
    except Exception:
        ranked = []
    return sample_material(ranked or chunks, budget)


async def call_model(prompt: str, max_tokens: int, model_config: dict, db: AsyncSession, user_id: int) -> str:
    """One model call with this app's standard failure messages, plus
    hosted-tier billing (same as the attempt endpoint)."""
    backend = model_config.get("backend", "local")
    try:
        result = await engines.model_router.run(prompt=prompt, max_tokens=max_tokens, **model_config)
    except Exception as exc:
        if backend == "local":
            raise HTTPException(
                status_code=503,
                detail="The free AI model isn't available on this server — add your own API key "
                "(or the hosted tier) in Account → AI model settings.",
            ) from exc
        raise HTTPException(status_code=502, detail=f"Your {backend} backend didn't respond: {exc}") from exc

    hosted_provider = model_config.get("hosted_provider")
    if hosted_provider:
        model_name = engines.model_router.DEFAULT_MODEL_NAMES[hosted_provider]
        await billing_service.charge_for_usage(db, user_id, hosted_provider, model_name, result.get("usage"))
        # Committed now, not with the caller's rows: the provider billed this
        # call even if its output then turns out unusable (a 502 below).
        await db.commit()
    return result.get("text") or ""


def _nothing_usable(what: str) -> HTTPException:
    return HTTPException(
        status_code=502,
        detail=f"The AI model didn't return usable {what} — try again, or use a stronger model in Account settings.",
    )


# --- concepts ---

_LIST_LINE_RE = re.compile(r"^(?:[-*•]|\d+[.)])\s+(.*)$")
_NAME_SPLIT_RE = re.compile(r"\s+[—–-]\s+|:\s+")


def concepts_prompt(material: str, existing: list[str]) -> str:
    avoid = f"\nAlready listed (do not repeat): {', '.join(existing[:40])}" if existing else ""
    return (
        "Below is a student's study material. List the 5 to 10 most important concepts in it.\n"
        "Output one per line and nothing else, each exactly like:\n"
        "- Concept name — one sentence defining it, based on the material"
        f"{avoid}\n\nMATERIAL:\n{material}"
    )


def parse_concepts(text: str) -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    seen: set[str] = set()
    for raw in text.splitlines():
        m = _LIST_LINE_RE.match(raw.strip().replace("**", ""))
        if not m:
            continue
        parts = _NAME_SPLIT_RE.split(m.group(1).strip(), maxsplit=1)
        name = parts[0].strip().rstrip(".")
        desc = parts[1].strip() if len(parts) > 1 else ""
        # A "name" longer than this is a sentence the model failed to split.
        if not name or len(name) > 80 or name.lower() in seen:
            continue
        seen.add(name.lower())
        out.append((name, desc))
    return out[:12]


# --- flashcards ---

def flashcards_prompt(material: str, count: int, focus: str | None) -> str:
    """Material first, then the instruction ending in a worked example —
    measured live 2026-10-07 on the free local model: with instructions
    first and the material last it summarised the material as answer-only
    lines in 2 of 2 runs (nothing parseable); this ordering gave usable
    cards in 3 of 3. Small models follow the most recent instruction."""
    about = f" about {focus}" if focus else ""
    return (
        f"STUDY MATERIAL:\n{material}\n\n"
        f"Turn the material above into exactly {count} flashcards{about}, using only facts from it. "
        "Each card is ONE line with a question, then ' | ', then its answer. Example of the exact format:\n"
        "Q: What is the function of the cell wall? | A: It gives the cell structure and protection.\n"
        "Q: Where does photosynthesis happen? | A: In the chloroplasts.\n\n"
        f"Now write the {count} flashcards about the study material, one per line:"
    )


_TERM_FRONT_MAX_WORDS = 8


def parse_flashcards(text: str, count: int) -> list[tuple[str, str]]:
    """Drops cards whose front is neither a question nor a short term —
    the free model sometimes copies a whole material sentence in as the
    "question" with an unrelated one-word "answer" (seen live: "Q:
    Mitochondria are double-membraned organelles… | A: Glucose")."""
    cards = engines.moderator._flashcards_from_text(text)
    usable = [
        (front, back) for front, back in cards
        if front.rstrip().endswith("?") or len(front.split()) <= _TERM_FRONT_MAX_WORDS
    ]
    return usable[:count]


# --- questions ---

def questions_prompt(concept: str, material: str, count: int) -> str:
    return (
        f"Write {count} practice questions testing understanding of \"{concept}\", using only the material below.\n"
        "Mix these three formats. Output one question per line and nothing else, exactly like:\n"
        "MCQ: question text | A) option | B) option | C) option | D) option | Answer: B\n"
        "TF: a statement that is either true or false | Answer: true\n"
        "SA: an open question | Answer: a model answer in one or two sentences\n\n"
        f"MATERIAL:\n{material}"
    )


_Q_KIND_RE = re.compile(r"^(?:[-*•]|\d+[.)])?\s*(MCQ|TF|SA)\s*[:.]\s*(.+)$", re.IGNORECASE)
_OPTION_RE = re.compile(r"^([A-Fa-f])\s*[).:]\s*(.+)$")
_ANSWER_RE = re.compile(r"^answer\s*[:.]\s*(.+)$", re.IGNORECASE)


def parse_questions(text: str, count: int) -> list[dict]:
    """Returns CreateQuestion-shaped dicts, each already valid for
    grading.py: mcq → correct_answer is one of `options` verbatim;
    true_false → "true"/"false"; short_answer → a non-empty model answer
    (LLM-graded). Anything malformed is dropped, not repaired by guessing."""
    out: list[dict] = []
    seen: set[str] = set()
    for raw in text.splitlines():
        m = _Q_KIND_RE.match(raw.strip().replace("**", ""))
        if not m:
            continue
        kind = m.group(1).upper()
        parts = [p.strip() for p in m.group(2).split("|") if p.strip()]
        if len(parts) < 2:
            continue
        prompt = parts[0]
        answer_match = _ANSWER_RE.match(parts[-1])
        if not answer_match or prompt.lower() in seen:
            continue
        answer = answer_match.group(1).strip()

        if kind == "MCQ":
            options: dict[str, str] = {}
            for p in parts[1:-1]:
                om = _OPTION_RE.match(p)
                if om:
                    options[om.group(1).upper()] = om.group(2).strip()
            letter = answer[:1].upper()
            if len(options) < 2 or letter not in options or len(set(options.values())) != len(options):
                continue
            q = {"type": "mcq", "prompt": prompt, "options": list(options.values()), "correct_answer": options[letter]}
        elif kind == "TF":
            verdict = answer.split()[0].strip(".").lower() if answer else ""
            if verdict not in ("true", "false"):
                continue
            q = {"type": "true_false", "prompt": prompt, "correct_answer": verdict}
        else:
            q = {"type": "short_answer", "prompt": prompt, "correct_answer": answer}
        seen.add(prompt.lower())
        out.append(q)
    return out[:count]
