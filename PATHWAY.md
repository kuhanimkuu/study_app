# Study OS — Build Pathway

> A feature-by-feature learning roadmap. Build small things, combine at the end.
> Nothing here is a monolith. Each item is a self-contained win.
> **Current phase: Python only. Flutter and Android come much later.**

---

## 0. The System Model (the shared mental picture)

Before building, this is the architecture we settled on. Everything below builds toward it.

```
Raw input (text / image / pdf / url)
        │
        ▼
INPUT ENGINE   ── extract & normalize by modality
        │          (OCR, PDF parse, fetch... all converge to text/content)
        │          Answers: "what did they GIVE me?"  (facts, not meaning)
        ▼
MODERATOR (the AI) ── the brain / decision-maker
        │          Answers: "what are they ASKING?"  (intent / meaning)
        │          Then: decide format → pick tools → WRITE the explanation → assemble
        ▼
ENGINES       ── compute/retrieve facts (math, graph, quiz, search...)
        │          resumable coroutines, produce raw data (no prose)
        ▼
MODERATOR     ── assemble engine facts + its own prose → response blocks
        │
        ▼
RESPONSE      ── blocks: text / equation / graph / quiz / ...
        │          (+ clarification, + error — can loop back to user)
        ▼
MEMORY LOG    ── record the activity, labelled (stateful)
```

### The role map (hotel analogy)

| Study OS | Hotel | Does | Does NOT do |
|---|---|---|---|
| **Input engine** | Waiter | take the order, extract/normalize (modality) | understand meaning |
| **Moderator (AI)** | Chef | decide how to prepare, **write the explanation**, plate/assemble | compute math, extract text |
| **Engines** | Line cooks / stations | compute/retrieve the **facts** (answer, steps, graph data) | write prose, make decisions |

### The key division of labour

- **Input engines are modality-specific, but dumb** — an OCR engine knows images, a PDF engine knows documents. They extract; they don't understand. They all converge to the same thing: text/content.
- **The moderator is modality-agnostic** — it never sees a raw image or PDF. It only sees text, so it asks "what does this want?" the same way regardless of source.
- **Engines produce raw truth; the moderator produces the words.** The `text` block ("you subtract 3 because...") is moderator-authored. The `equation`/`graph`/`table` blocks are engine-sourced.

### State (the moderator remembers)

1. **Pending context** — short-term: "what did I just ask the user?" (cleared once answered — drives the clarification loop).
2. **Activity table** — long-term: one big log, properly **labelled** for quick search. ("quiz me on what I struggled with yesterday" = a query over labelled events.)

---

## 1. The Phases (current = Phase 1)

### Phase 1 — Python engines, independently (NOW)
Each engine is a plain `.py` file, run in a terminal:
- `math_engine.py` → sympy
- `pdf_engine.py` → PyMuPDF
- `ocr_engine.py` → pytesseract

**Engines are written as resumable coroutines** (`async def` / generators) from day one —
so the future scheduler can pause/resume them without a rewrite. This is deliberately
not-simple; it's a learning goal, not an overhead to avoid.

### Phase 2 — The input engine + moderator (make them work together)
- `input_engine.py` — classify/normalize: "what did they give me?" (text vs image vs pdf vs math).
- `moderator.py` — the decision-maker: understand intent → decide format → pick tools → assemble.

First as **rule-based logic** (no model). Swap in a real LLM later.

### Phase 3 — Flutter UI (later)
Renderers that consume the JSON the moderator already produces. Built against *real* output, not stubs.

### Phase 4 — The join (last)
Pipe Python JSON through the interop bridge into Flutter, on a real phone.
See: `STEPS_python_on_android.md`.

---

## 2. How to Build an Engine (the order that matters)

The JSON is **the last 10%, not the first.** You can't package something that doesn't work yet.

1. **Make it work** — get the real logic right (sympy solves it, PyMuPDF extracts it, etc.).
2. **Test input/output** — run it, `print()` everything, look at the raw result. Is it right? Is it useful?
3. **Wrap it in a dict** — only *then* put the result in a JSON-serializable dict, based on what you actually got.

```python
# Step 1 & 2: get the real result working first
result = sympy.solve(equation, x)
print(result)          # ← look at this FIRST. Correct? Useful?
# → [2]

# Step 3 (later): wrap it nicely
return {"type": "math", "answer": str(result)}
```

**The one rule to remember (not design around):** the final dict must only contain
strings, numbers, booleans, `None`, lists, and dicts — nothing Python-specific.

---

## 3. The Output Convention

The JSON structure is documented in **`json.md`** as it evolves — we discover it
feature-by-feature (inputs → outputs → decide the shape), not up front.

The current skeleton (three tiers):

1. **Request** — user → input engine → moderator.
2. **Engine I/O** — moderator ↔ engine (each engine has its own shape).
3. **Response** — moderator → Flutter (assembled blocks).

See `json.md` for the full pipeline of shapes.

---

## 4. The Feature Queue (in order)

Each item is a self-contained win. Build in roughly this order.

### Phase 1 — Python engines, independently (no Flutter, no phone, no model)
- [ ] **1. Math Engine** — typed math → sympy/numpy. Coroutine. Make it work, print raw output, then wrap in a dict.
- [ ] **2. PDF Engine** — PyMuPDF extracts real text.
- [ ] **3. OCR Engine** — pytesseract extracts text from images.

### Phase 2 — Input engine + moderator (rule-based, no model)
- [ ] **4. Input Engine** — classify/normalize input: "what did they give me?" (modality → text).
- [ ] **5. Moderator (rule-based)** — understand intent → decide format → pick tools → assemble response.

### Phase 3 — Flutter UI (later, against real output)
- [ ] **6. Block Renderer** — renders `text`, `equation`, `graph`, `quiz` blocks from real JSON.
- [ ] **7. Graph Block** — render an equation as a chart.
- [ ] **8. Quiz Block** — render question + options + reveal answer.

### Phase 4 — The Hard Parts
- [ ] **9. Math OCR** — photograph a handwritten/typed question → parse → solve. (The Photomath problem. Attempt, learn, fail, iterate.)
- [ ] **10. Vision model** — diagram/table understanding. (Different model family — text models won't do this.)

### Phase 5 — The Brain
- [ ] **11. Local LLM** — llama.cpp on device, replacing the rule-based moderator.
- [ ] **12. Response steering** — the model chooses the output format (text vs graph vs steps) and authors the explanation.

### Phase 6 — The Join (the last thing)
- [ ] **13. Interop Bridge** — Chaquopy/serious_python: pipe Python JSON → Flutter renderers on a real phone.

---

## 5. What Can Be Stubbed (and when)

| Thing | Stub | Replace with real |
|---|---|---|
| Moderator | Rule-based `if` statements | llama.cpp (Phase 5) |
| Explanation prose | Hardcoded templates | Moderator-authored (Phase 5) |
| Graph data | Hardcoded points | sympy/matplotlib output (Phase 3) |
| Quiz data | Fake questions | Generated from material (later) |
| Input text | Typed strings | OCR / PDF (Phase 1) |
| Math solving | (none — sympy IS real) | — |
| Memory log | In-memory list | SQLite / JSON file (later) |

**Key idea:** the LLM is stubbed until Phase 5. Everything before it works without a model.

---

## 6. What We're Deliberately NOT Doing (yet)

- No Flutter until Phase 3 (after the engines + moderator work).
- No Android/Chaquopy until the join (Phase 6).
- No 3D, animations, simulations, YouTube, research engine — all deferred / optional.
- No vision model until the text-only core works.
- No monolith — features stay independent files/engines.

---

## 7. Definition of Done (for each engine)

An engine is "done" when:
- [ ] It runs standalone in a terminal (`if __name__ == "__main__":`).
- [ ] It's a **resumable coroutine** (can pause, yield partial results, resume).
- [ ] The raw output is **correct** (checked with `print()`, eyeballed).
- [ ] The raw output is **useful** (you can see what a Flutter UI would show).
- [ ] It returns a JSON-serializable dict (the last step, and it's trivial).
- [ ] You learned something. (This is a pet project — breakage is fine.)

---

*This is a living document. Reorder, cut, add as fun dictates. The queue is a menu, not a commitment.*
