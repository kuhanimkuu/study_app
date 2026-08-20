# Study OS — JSON Structure (living contract)

> This document captures the JSON shapes as we discover them.
> We do NOT design everything up front — we map features (see `features.md`)
> to inputs/outputs, then decide the shapes, then record them here.
> **Status: skeleton only. Shapes get filled in feature-by-feature.**

---

## 1. The Pipeline of Shapes

Every request flows through these shapes. There are five, not just "request/response",
because the input engine and moderator sit in the middle and each has its own contract.

```
1. RAW INPUT      user → input engine       what the user literally gave
2. CLASSIFIED     input engine → moderator  "what did they give me?" (normalized)
3. MODERATOR PLAN moderator → engines       "which tools, in what order?"
4. ENGINE RESULT  engines → moderator       raw facts from each tool
5. RESPONSE       moderator → Flutter       assembled blocks (the final answer)
```

The moderator is the translator sitting in the middle of all of them.

---

## 2. Shape 1 — Raw Input (user → input engine)

What the user literally provides, before any processing.

```json
{
  "input_type": "text | image | pdf | url | audio",
  "content": "<raw bytes / string / file reference>",
  "mode": "learn | solve | practice | quiz | research | revise | create | explore | null",
  "requested_format": "text | graph | quiz | ... | null",
  "project": "fluid_mechanics | null"
}
```

- `mode` — the broad task type (may be null → detected later).
- `requested_format` — explicit user preference. `null` = moderator must reason the best format.
- `project` — which knowledge-base project this belongs to (may be null).

---

## 3. Shape 2 — Classified Content (input engine → moderator)

The input engine normalizes *modality* into *content*. It reports **facts** about what's
there — never meaning. After this point, the moderator no longer knows or cares whether
the text came from a photo, a PDF, or typed input.

```json
{
  "content": "Solve 2x + 3 = 7",          // the extracted/normalized text
  "detected": ["math"],                   // facts about content: math | table | graph | ...
  "input_type": "image",                  // original modality (for context, optional)
  "metadata": {                           // modality-specific extras
    "source": "camera",
    "confidence": 0.92
  }
}
```

Key point: **all input engines converge to this same shape** — text + detected facts.
That's what keeps the moderator universal.

---

## 4. Shape 3 — Moderator Plan (moderator → engines)

The moderator's decisions: intent, chosen format, and which engines to call.

```json
{
  "intent": "solve",                       // what are they asking? (the meaning)
  "response_format": "equation + steps",   // chosen format (respected if requested)
  "engines": [                             // tools to call, in dependency order
    { "name": "math_engine", "args": { "expression": "2x + 3 = 7" } },
    { "name": "graph_engine", "args": { "expression": "2x + 3 = 7" }, "depends_on": "math_engine" }
  ]
}
```

- `depends_on` — later, for the scheduler (multi-tool with dependencies). v1 is mostly single-engine.

---

## 5. Shape 4 — Engine Result (engines → moderator)

Each engine returns **raw facts** — no prose, no explanation. Just the computed truth.

```json
{
  "engine": "math_engine",
  "status": "ok | error",
  "result": {
    "answer": 2,
    "steps": ["2x = 4", "x = 2"],
    "latex": "x = 2"
  }
}
```

On failure (Shape 4b):

```json
{
  "engine": "math_engine",
  "status": "error",
  "error": "could not parse expression"
}
```

The moderator receives this and decides: retry? ask the user? fall back to text?
The failure is **reported, never hidden**.

---

## 6. Shape 5 — Response (moderator → Flutter)

The assembled answer. This is the **block protocol** — the moderator's vocabulary for
expressing an answer. Two origins of content:

- **Moderator-authored** blocks (the explanation/prose).
- **Engine-sourced** blocks (facts, equations, graphs, tables).

```json
{
  "blocks": [
    { "type": "text",     "content": "Here's how to solve it: ...",  "source": "moderator" },
    { "type": "equation", "latex": "x = 2",                          "source": "math_engine" },
    { "type": "graph",    "data": { "...": "..." },                  "source": "math_engine" }
  ],
  "session_id": "abc123"
}
```

### Response block types

**Standard blocks (from spec §20):**
`text`, `equation`, `interactive_graph`, `diagram`, `animation`, `3d`, `video`, `pdf`, `quiz`, `table`, `source`

**System blocks (added by us):**

```json
{ "type": "clarification", "question": "What would you like me to do with this?" }
```
```json
{ "type": "error", "engine": "math_engine", "message": "could not parse expression" }
```

- `clarification` — moderator asks the user (ambiguous input). Drives the conversational loop.
- `error` — an engine failed; the moderator surfaces it honestly rather than guessing.

---

## 7. State / Memory (the moderator remembers)

The system is **stateful**. Two kinds of state.

### 7a. Pending context (short-term)
What the moderator just asked, so it can link the user's next input to the clarification.

```json
{
  "session_id": "abc123",
  "pending": {
    "asked": "What would you like me to do with this PDF?",
    "context": { "input_type": "pdf", "content_ref": "ch3.pdf" }
  }
}
```

### 7b. Activity table (long-term)
One big log, **labelled** for fast searching. "Quiz me on what I struggled with yesterday"
becomes a query over these labelled events.

```json
{
  "event": "quiz",
  "topic": "thermodynamics",
  "score": 0.4,
  "timestamp": "2026-08-03T08:00:00Z",
  "labels": ["struggle", "thermo", "quiz"]
}
```

---

## 8. The Discovery Process (how this doc fills in)

We fill this in feature-by-feature, not all at once. For each feature in `features.md`:

1. **What's the input?** (→ shapes 1 & 2)
2. **What's the output?** (→ shapes 4 & 5)
3. **What blocks does the output need?** (→ shape 5, block list)
4. **Does the moderator need to ask?** (→ clarification / pending state)

Then the shape is decided and recorded here. JSON is the **last** thing we design for any
given engine — after it actually works (see `PATHWAY.md` §2).

---

## 9. Open Questions (to settle as we go)

- [ ] Where exactly does "detection" (e.g. "there's math here") end and "intent" ("they want to solve it") begin?
- [ ] Full list of `detected` facts the input engine can report.
- [ ] Memory storage backend (in-memory → SQLite / JSON file → ?).
- [ ] How the scheduler expresses parallel vs sequential execution (v2).

---

*Living document. Update it whenever a new feature's input/output shape is decided.*
