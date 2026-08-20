# Study OS

A local-first, on-device AI study companion. The user gives it material (text, photos, PDFs, links) and asks a question — and instead of just chatting back, it decides **how** to answer: as an equation, a graph, a quiz, a diagram, a document, and so on.

> **Note:** this is a **personal learning project**. Things are allowed to break, be incomplete, or not work as intended. The goal is to understand the tech, not to ship a product.

---

## What it is (and isn't)

- ✅ A study **environment** — holds material, remembers progress, chooses its output format.
- ✅ **Local-first** — models and data live on the device.
- ✅ **Deterministic engines** do the real work (math, PDF, OCR, search); the AI orchestrates and explains.
- ❌ **Not a chatbot.** The LLM is not the brain of everything.

For the full original vision, see [`study_os_overview-v2.pdf`](study_os_overview-v2.pdf).

---

## The architecture in one picture

```
user input (text / image / pdf / url)
        │
        ▼
INPUT ENGINE   ── extract & normalize (modality → plain text + detected elements)
        │
        ▼
MODERATOR (AI) ── understand intent
        │         ── decide the response format (respect request OR reason best fit)
        │         ── pick the engines (tools)
        │         ── WRITE the explanation prose
        ▼
ENGINES       ── compute/retrieve the facts (resumable coroutines)
        │
        ▼
MODERATOR     ── assemble facts + its own prose → response blocks
        │
        ▼
[ clarify / error / respond ]   ← can loop back
        │
        ▼
MEMORY LOG    ── record the activity, labelled
```

### Division of labour (the "carpenter / hotel" model)

| Component | Role | Does **not** do |
|---|---|---|
| **Input engine** | extract/normalize (deals with *modality*) | understand meaning |
| **Engines** | compute/retrieve *facts* (answer, graph data, extracted text) | write prose, decide anything |
| **Moderator (AI)** | understand intent → choose format → route → **author the explanation** → assemble | compute math, extract text |

- Input engines converge everything to **text/content**, so the moderator stays universal.
- Engines produce **raw truth**; the moderator produces **the words** that make it teachable.

### Key decisions (locked)

- The system is **stateful** — clarification loop (short-term pending context) + labelled activity log (long-term memory).
- Engines are **resumable coroutines** from day one, so a future scheduler can pause/resume and manage dependent calls.
- Response vocabulary = the spec's block types (`text`, `equation`, `graph`, `diagram`, `animation`, `3d`, `video`, `pdf`, `quiz`, `table`, `source`) **+** two system blocks: `clarification`, `error`.

---

## Build order (Python first, Flutter last)

1. **Phase 1 — Engines (Python only, in a terminal).** Each feature is its own folder with a standalone `engine.py`. Build → test with `print()` → wrap output in a JSON-serializable dict **last**.
2. **Phase 2 — Input engine + Moderator.** Make them work together. The moderator starts as **rule-based**, swapped for a real LLM later.
3. **Phase 3 — Flutter UI.** Render whatever JSON comes back. Fed by stubs first.
4. **Phase 4 — Join.** Pipe the JSON through the Android bridge (see [`STEPS_python_on_android.md`](STEPS_python_on_android.md)).
5. **Phase 5 — The real brain.** Local LLM (llama.cpp) replaces the stub moderator.

> **Rule of thumb:** JSON is the *last 10%* of an engine, not the first. Make it work, then shape the dict. The output shape reveals itself after you see real results.

---

## Repository layout

```
study_app/
├── README.md                     ← you are here
├── PATHWAY.md                    ← how we build (phases, rules, definition of done)
├── features.md                   ← the feature inventory (input / output / status)
├── json.md                       ← the data contract (shapes, blocks, memory)
├── STEPS_python_on_android.md    ← how to run Python on the phone (Chaquopy)
├── study_os_overview-v2.pdf      ← the original spec
└── features/                     ← one folder per feature
    ├── README.md                 ← the per-feature convention
    └── <category>/<feature>/
        ├── README.md             ← input / output / status
        ├── skeleton.py           ← the Python structure + JSON contract (reference)
        └── engine.py             ← comments only (what it should do)
```

---

## The docs, in one line each

| Doc | Purpose |
|---|---|
| **PATHWAY.md** | The roadmap and rules. How we build, in what order, and what "done" means. |
| **features.md** | The full feature inventory — every capability, its input/output, and v1 status. |
| **json.md** | The data contract — the pipeline of JSON shapes, response blocks, and memory. |
| **STEPS_python_on_android.md** | Step-by-step guide for embedding Python (CPython) into the Flutter app via Chaquopy. |

---

## Building a feature (the convention)

1. Read `features/<category>/<feature>/README.md` for input/output/status.
2. Read `skeleton.py` for the intended structure + JSON contract.
3. Build in `engine.py` — make it work, test with `print()`, wrap in a dict last.
4. Update `json.md` **only if** the real output shape differs from the skeleton's assumption.

---

## Tech stack (eventual)

- **Flutter** — UI
- **Python (embedded via Chaquopy)** — engines + moderator
- **CPython** — the interpreter Chaquopy bundles onto Android
- **sympy / numpy** — math
- **PyMuPDF / pytesseract** — PDF / OCR
- **llama.cpp** — local LLM inference (Milestone 5)

---

## Current status

- [x] Architecture settled (pipeline, division of labour, state model)
- [x] Docs written (`PATHWAY.md`, `features.md`, `json.md`)
- [x] Feature folder structure created (42 features, skeleton + engine stubs)
- [ ] First engine built (`math_engine/symbolic/` — recommended next step)
- [ ] Moderator built
- [ ] Flutter UI
- [ ] Android integration
- [ ] Local LLM

**Next step:** build the first real engine — `features/math_engine/symbolic/engine.py` — using sympy, tested in a terminal.
