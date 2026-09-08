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

## Running it

Two pieces: a Python/FastAPI server (does the actual work) and a Flutter client (renders the results). Local-first and self-hosted — there is no cloud backend anywhere in this.

### 1. Server

```
pip install -r requirements.txt
python -m uvicorn server.main:app --host 0.0.0.0 --port 8000
```

`--host 0.0.0.0` matters if you're testing from a real phone (see below) — it's what lets `adb reverse` reach it. Verify it's up: `curl http://127.0.0.1:8000/api/health` should return `{"status":"ok"}`.

The local LLM (`Qwen2.5-0.5B-Instruct`) downloads automatically on first real use, via `huggingface_hub` — needs internet the first time, cached under `~/.cache/huggingface` after that, nothing to set up manually. See `requirements.txt`'s own note if `torch` doesn't resolve to a CPU build.

### 2. Flutter client

```
cd frontend
flutter pub get
flutter run              # or: flutter build apk --release
```

Point it at your server — the in-app **Settings** (gear icon on the login screen or the Chat screen) lets you set the server URL. Defaults (`frontend/lib/core/api/default_base_url.dart`):

- **Android emulator** → `10.0.2.2:8000` (the emulator's alias for its host machine). Default, no setup needed.
- **Windows desktop / web** → `127.0.0.1:8000`. Default, no setup needed.
- **A real Android device** → neither default works. Either put the server's real LAN IP in Settings (same Wi-Fi network, server port reachable through any firewall), or — the way this was actually tested end-to-end — connect over `adb` and tunnel the port instead:
  ```
  adb reverse tcp:8000 tcp:8000
  ```
  then set the app's server URL to `http://127.0.0.1:8000`. The tunnel only lasts as long as that `adb` connection does — a dropped/renegotiated wireless-debugging session drops it too and it needs re-running; a USB connection is more stable for this if it keeps happening.

**Real-device notes from actually doing this** (a Xiaomi/MIUI phone): MIUI blocks `adb install` by default — enable **Developer options → Install via USB** first, or installs fail with `INSTALL_FAILED_USER_RESTRICTED`. A release build also needs the `INTERNET` permission and a `network_security_config.xml` cleartext exception for `127.0.0.1`/`10.0.2.2` explicitly declared — Flutter's template only grants `INTERNET` to debug/profile builds, not release, which is a real bug this project hit (silent, unhelpful `SocketException`s) and fixed; both are already committed here, so a fresh clone doesn't need to rediscover this.

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
DEVICE        ── persists the activity, labelled (local-first, see below)
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

- The system is **stateful** — clarification loop (short-term pending context, in-memory on the server) + labelled activity log (long-term memory, local-first — lives on the device, not the server; see "Architecture note: local-first data" below).
- Engines are **resumable coroutines** from day one, so a future scheduler can pause/resume and manage dependent calls.
- Response vocabulary = the spec's block types (`text`, `equation`, `graph`, `diagram`, `animation`, `3d`, `video`, `pdf`, `quiz`, `table`, `source`) **+** two system blocks: `clarification`, `error`.

---

## Build order (Python first, Flutter last)

1. **Phase 1 — Engines (Python only, in a terminal).** Each feature is its own folder with a standalone `engine.py`. Build → test with `print()` → wrap output in a JSON-serializable dict **last**.
2. **Phase 2 — Input engine + Moderator.** Make them work together. The moderator starts as **rule-based**, swapped for a real LLM later.
3. **Phase 3 — Flutter UI.** Render whatever JSON comes back. Fed by stubs first.
4. ~~**Phase 4 — Join.** Pipe the JSON through the Android bridge (see `STEPS_python_on_android.md`).~~
5. ~~**Phase 5 — The real brain.** Local LLM (llama.cpp) replaces the stub moderator.~~

> **Rule of thumb:** JSON is the *last 10%* of an engine, not the first. Make it work, then shape the dict. The output shape reveals itself after you see real results.

> **Phases 4–5 didn't happen as originally planned.** `STEPS_python_on_android.md` describes embedding Python on-device via Chaquopy — abandoned mid-build once Chaquopy turned out to have no PyMuPDF/Tesseract support (see Architecture note 1 below); that doc is now a historical record of the research, not a step to follow. `llama.cpp` was swapped for PyTorch + `transformers` (no prebuilt `llama-cpp-python` wheels were available). What actually joined everything was a FastAPI server (Phase 4's real equivalent) and a local model running behind that server (Phase 5's real equivalent) — see "Running it" above and Architecture notes 1–2 below.

---

## Repository layout

```
study_app/
├── README.md                     ← you are here
├── requirements.txt              ← Python deps for server/ + features/ (pip install -r)
├── PATHWAY.md                    ← how we build (phases, rules, definition of done)
├── features.md                   ← the feature inventory (input / output / status)
├── json.md                       ← the data contract (shapes, blocks, memory)
├── STEPS_python_on_android.md    ← historical: the abandoned Chaquopy on-device plan
├── study_os_overview-v2.pdf      ← the original spec
├── features/                     ← one folder per feature/engine
│   ├── README.md                 ← the per-feature convention
│   └── <category>/<feature>/
│       ├── README.md             ← input / output / status
│       ├── skeleton.py           ← the Python structure + JSON contract (reference)
│       └── engine.py             ← the real implementation
├── server/                       ← FastAPI HTTP server — see server/README.md
│   ├── main.py, db.py, crypto.py, security.py, engines.py
│   └── routers/                  ← auth.py, account.py, projects.py, ask.py, health.py
└── frontend/                     ← Flutter client (Android/Windows/web)
    └── lib/
        ├── core/                 ← api client, auth, crypto, local storage, settings
        ├── app/                  ← AuthGate, AppShell (top-level navigation)
        └── features/             ← chat, projects, history, account, auth (screens/widgets)
```

---

## The docs, in one line each

| Doc | Purpose |
|---|---|
| **PATHWAY.md** | The roadmap and rules. How we build, in what order, and what "done" means. |
| **features.md** | The full feature inventory — every capability, its input/output, and v1 status. |
| **json.md** | The data contract — the pipeline of JSON shapes, response blocks, and memory. |
| **server/README.md** | The HTTP API — every endpoint, the local-first architecture (what the server does and doesn't store), and the bugs found/fixed building it. |
| **features/moderator/README.md** | How free text gets routed to an engine (or the general-conversation LLM fallback) — the routing table and every real bug found in it. |
| **STEPS_python_on_android.md** | *Historical.* The abandoned Chaquopy on-device plan — see Architecture note 1 below for why. |

---

## Building a feature (the convention)

1. Read `features/<category>/<feature>/README.md` for input/output/status.
2. Read `skeleton.py` for the intended structure + JSON contract.
3. Build in `engine.py` — make it work, test with `print()`, wrap in a dict last.
4. Update `json.md` **only if** the real output shape differs from the skeleton's assumption.

---

## Tech stack (as actually built — see requirements.txt for exact versions)

- **Flutter** — UI (Android, Windows desktop, web)
- **FastAPI + uvicorn** — the HTTP server; Python engines run server-side, not embedded on-device (see Architecture note 1)
- **PyTorch + `transformers`** — local LLM inference (`Qwen2.5-0.5B-Instruct`), CPU-only
- **sympy / numpy / scipy / pint** — math (solve, differentiate, integrate, numeric, unit conversion)
- **PyMuPDF (`fitz`) / pytesseract / opencv** — PDF processing / OCR / image analysis
- **matplotlib / reportlab / pygltflib** — generated graphs, images, PDFs, and 3D models
- **fastembed** — local embeddings for RAG/project search
- **faster-whisper** — audio transcription
- **sqflite (client) / SQLite (server)** — on-device storage and the server's minimal auth DB
- **anthropic / openai SDKs** — BYOK hosted-model backends, used only with a user's own key

---

## Current status

- [x] Architecture settled (pipeline, division of labour, state model)
- [x] Docs written (`PATHWAY.md`, `features.md`, `json.md`)
- [x] Feature folder structure created (42 features, skeleton + engine stubs)
- [x] **39 of 42 features implemented and tested for real** — every category built: `math_engine`, `ocr/*` (text, handwriting, tables, graphs, diagrams, math, image understanding), `document_engine`, `rag`, `image_processing`, `input_pipeline` (text/image/pdf/audio/web/project), `personalization`, `research_engine` (including live web search), `document_generation` (real PDF output), `visual_explanation` (images, diagrams, interactive 2D, animations, 3D models, physics simulation). The 3 not built: `model_router`'s siblings in `voice/*` (deliberately out of scope — client-native, see `features/voice/*/README.md`) — `model_router` itself is now built (see below).
- [x] Moderator built and LLM-upgraded — rule-based intent inference/engine routing (kept, doesn't need an LLM) + **real local-LLM-authored explanation prose** for math routes (upgraded from templates, see below), clarification loop, in-memory memory log.
- [x] **Local LLM integrated** (`model_router`) — a real local `Qwen2.5-0.5B-Instruct` model (PyTorch + `transformers`, CPU inference) running behind a pluggable backend interface, matching `features.md`'s own "tiny model" spec. `llama-cpp-python` (the original spec's choice) ships no prebuilt wheels and needs CMake, unavailable here — `transformers` was the reliable substitute; the backend is swappable (e.g. to a hosted API) without touching callers.
- [x] **HTTP server built and tested** (`server/`, FastAPI, modular `routers/` package) — exposes `/api/ask/{text,image,pdf,audio,web,project}`, `/api/auth/*`, `/api/account`, `/api/health`. Every endpoint tested against a real running server, including a full multi-turn PDF flow (upload -> clarification -> query-only follow-up, no re-upload), a full voice pipeline (synthesized speech -> Whisper transcription -> spoken-math normalization -> symbolic solve -> LLM-authored explanation), real multi-user auth (JWT + bcrypt), and a real BYOK round-trip (client-side AES-256-GCM encrypt -> server decrypt -> genuine outbound call to Anthropic's API). See `server/README.md` and `features/moderator/README.md` for the bugs surfaced and fixed by this testing.
- [x] **Flutter UI built** (`frontend/`, feature-first architecture mirroring `features/README.md`'s own convention) — a multi-screen app (projects, chat, history, account), not just a chat window: real auth (signup/login/logout), a modular block-rendering system (one widget per block type, easy to extend), on-device local storage for chat history/BYOK settings (see below), and a ChatGPT-style sidebar over multiple general-chat sessions (list, resume, start new, delete — verified against a real sqflite database, not just `flutter analyze`). Now running on a real physical Android device (see the Android integration entry below), not just Windows desktop / `flutter test`/`flutter analyze`.
- [x] **Projects ("notebooks") wired up end-to-end** — a NotebookLM-style workspace per project: Sources (add material — pasted text or a PDF/txt upload), Chat (query it), and Studio (generate real PDFs — study guides, flashcards, practice exams, etc. — over the project's material via `document_generation/generate_docs`, tracked per-project/per-user in `db.py`'s `generated_artifacts` table) tabs, all scoped per-user server-side (see "Architecture note 2" below for why projects are the one exception to local-first). `rag/projects` existed since early in the build but had no caller until now; verified over real HTTP end-to-end for all three tabs, including fetching a generated PDF back and confirming real `%PDF` magic bytes, and per-user isolation (two users creating identically-named projects, no collision). Project chat returns matching source chunks rather than an LLM-synthesized answer — a documented scope boundary, not an oversight (see `moderator/README.md`). A general chat session can also be converted into a project directly from ChatScreen's AppBar ("Convert to project") — compiles that session's Q&A into one text blob and feeds it through the same create-project/add-material calls the Projects screen uses, no new backend endpoint needed; the original chat is left untouched. Verified end-to-end over real HTTP (create → add compiled Q&A material → immediately queryable, correctly ranked).
- [x] **Export a graph as a downloadable PDF** — "draw a graph of y=3x+2" (or "give me a pdf of...", "generate a pdf of...") now produces a real vector PDF (matplotlib's Agg backend, not a raster conversion), not just interactive point data or a PNG. Built in response to real-device testing that surfaced the gap; along the way, found and fixed a deeper bug in the same expression-extraction logic multiple text-triggered math routes share — see `features/moderator/README.md`'s numbered bug list (#8) for the full story.
- [x] **Android integration — running on a real physical device**, not just an emulator. Release build (not debug), installed via `adb` over wireless debugging. Two real bugs found and fixed getting there: the release `AndroidManifest.xml` was missing the `INTERNET` permission (Flutter's template only grants it to debug/profile builds by default — every network call silently failed with an unhelpful `SocketException`), and Android's default cleartext-HTTP block needed a scoped `network_security_config.xml` exception for `127.0.0.1`/`10.0.2.2` (this server has no TLS — a dev/local-first choice, not an oversight). See "Running it" above for the full real-device setup, including the MIUI-specific `adb install` gotcha.
- [x] **`requirements.txt` added** — the repo had no Python dependency manifest until this point; a fresh clone would `ImportError` immediately. Scoped to what the code actually imports (verified by grepping every `features/*/engine.py` and `server/*.py`), not a raw `pip freeze` — that would have shipped ~160 packages from unrelated projects on the dev machine. Verified via `pip install -r requirements.txt --dry-run` resolving cleanly.

**Architecture note 1 (decided during build, not in the original spec):** the project targets a **server-hosted Python backend**, not on-device Chaquopy-embedded Python. Verified against Chaquopy's actual current package index that PyMuPDF and Tesseract/OCR have no supported native build for Android — so a server backend avoids that dead end entirely; the Flutter app becomes a thin client. See `document_engine/scanned_ocr/README.md` for the research that drove this and the Android-native fallback (`PdfRenderer` + ML Kit Text Recognition v2) if an offline/on-device mode is ever revisited.

**Architecture note 2 (a second pivot, layered on top of note 1): local-first data.** The server-hosted backend from note 1 does the *compute* (math, OCR, search, LLM prose) but deliberately does not become the source of truth for the user's own data. `server/db.py` stores only auth essentials (email, password_hash, display_name) plus a per-user AES-256-GCM key; chat history, the activity/progress log, and BYOK model settings all live on the device (`frontend/lib/core/storage/local_db.dart`, `.../settings/model_settings_service.dart`) and are sent to the server only per-request, only when a specific call needs them, never persisted server-side. This is what lets login work as a real "device handshake" — the server hands back a user's own key at login so a reinstalled app can recover access to its previously-encrypted local data — without the server ever holding a durable copy of what the user actually studied. See `server/README.md`'s "Architecture note: local-first data" for the full contract, and `frontend/test/user_crypto_test.dart` for the verified cross-language crypto compatibility this depends on.

**Next step:** the app is now genuinely running end-to-end on a real device, so the frontier has shifted from "does it work at all" to "how honest is what it can already do." A few concrete open items, each already flagged where it lives rather than silently left: `moderator/README.md`'s "struggle" detection is still a manual self-report, not real inference from a conversation's back-and-forth; `PdfBlockView`/`Model3dBlockView` open generated files externally (a real browser download) rather than rendering them inline in-app; and `frontend/README.md` is still Flutter's generic scaffolded boilerplate, unlike every other README in this repo. Also worth doing if wireless-debugging tunnel drops (see "Running it") keep being disruptive during dev: switch to a USB connection, which doesn't renegotiate the same way.
