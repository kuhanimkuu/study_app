# Study OS — Feature Inventory

> The complete list of features described in the spec, grouped by category.
> This is the source for the JSON mapping exercise: for each feature we'll
> decide its input → output → block types → JSON shape (recorded in `json.md`).
>
> **Marking guide:**
> - ✅ = core v1 (build first)
> - ⏳ = later phase
> - 🚫 = deferred / optional

---

## 1. Input Pipeline

| Feature | Input | Output | Status |
|---|---|---|---|
| Text question | typed string | content → moderator | ✅ |
| Image (camera/gallery/file/screenshot) | image bytes | content (via OCR/vision) | ✅ |
| PDF (notes/textbook/past paper/assignment) | PDF file | text + structure | ✅ |
| Web (URL / search / YouTube) | URL | fetched content | ⏳ |
| Audio (spoken question) | voice | text (via ASR) | ⏳ |
| Project material ("my Fluid Mechanics project") | project ref | stored knowledge context | ⏳ |

---

## 2. Image Processing

| Feature | Input | Output | Status |
|---|---|---|---|
| Quality analysis | image | blur/noise/resolution/lighting/perspective/rotation + "is it a document?" | ✅ |
| Adaptive enhancement | image | deblur/denoise/sharpen/contrast/exposure/perspective-correct/deskew/crop | ✅ |
| Content identification (vision routing) | image | route → text / handwriting / math / graph / diagram / photo / table | ⏳ |

---

## 3. OCR & Recognition

| Feature | Input | Output | Status |
|---|---|---|---|
| Text OCR (printed) | image | text | ✅ |
| Handwriting recognition | image | text | ⏳ |
| Math OCR → LaTeX | image | LaTeX equation | ⏳ (hard) |
| Table extraction | image/pdf | structured table | ⏳ |
| Graph/data extraction | image | data points | ⏳ |
| Diagram understanding | image | structured diagram | ⏳ |
| Image understanding | image | description/semantics | 🚫 |

---

## 4. Document Engine

| Feature | Input | Output | Status |
|---|---|---|---|
| PDF processing | PDF | metadata, text, page structure, images, tables, equations | ✅ |
| OCR on scanned pages | PDF (scanned) | text | ⏳ |
| Searchable knowledge | PDF + query | "summarize ch 3", "find everything about entropy", "explain pages 42–47", "answer Q8" | ⏳ |

---

## 5. Local RAG / Knowledge Base

| Feature | Input | Output | Status |
|---|---|---|---|
| Chunking + embedding + vector index | documents | searchable index | ⏳ |
| Semantic search | query | relevant chunks | ⏳ |
| Projects (Thermodynamics, Fluid Mechanics...) | material | organized knowledge | ⏳ |

---

## 6. Research Engine

| Feature | Input | Output | Status |
|---|---|---|---|
| Intent analysis | query | "needs external info?" | ⏳ |
| Search → discover → fetch → parse → clean → rank → dedupe → extract | query | curated sources | 🚫 (server-class work) |
| Source types | — | websites, YouTube, papers, images, interactive | 🚫 |

---

## 7. Math Engine

| Feature | Input | Output | Status |
|---|---|---|---|
| Symbolic (arithmetic, algebra, calculus, differentiation, integration, equations, matrices) | expression | symbolic answer + steps | ✅ |
| Numeric (numerical methods, statistics, probability) | expression | numeric answer | ✅ |
| Unit conversion | value + units | converted value | ⏳ |
| Graphing | expression | graph data/points | ✅ |

---

## 8. Visual Explanation

| Feature | Input | Output | Status |
|---|---|---|---|
| Static images (PNG/JPEG/WebP) | data | image | ⏳ |
| Diagrams (structured/editable) | data | diagram | ⏳ |
| Interactive 2D (SVG/canvas/native) | data | interactive visual | ⏳ |
| Animations (step-by-step sequence) | data | animation | 🚫 |
| Interactive 3D (GLB/glTF) | data | 3D model | 🚫 |
| Simulations (physics, engineering, math, chemistry, mechanics, thermo, fluids, circuits, electronics, structural, stats, economics) | parameters | interactive simulation | 🚫 |

---

## 9. Document Generation / PDF Output

| Feature | Input | Output | Status |
|---|---|---|---|
| Generate docs | material | revision notes, formula sheets, study guides, lab reports, summaries, practice exams, flashcard PDFs, worksheets | ⏳ |

---

## 10. Response Protocol — Block Types (the moderator's vocabulary)

`text`, `equation`, `interactive_graph`, `diagram`, `animation`, `3d`, `video`, `pdf`, `quiz`, `table`, `source`

Plus the **system blocks** we added:
- `clarification` — moderator asks the user (ambiguous input)
- `error` — engine failed, surfaced honestly

---

## 11. AI / Model Router

| Model | Size | Job | Status |
|---|---|---|---|
| Tiny model | ~0.3–0.6B | classification, routing, extraction | ⏳ |
| Main model (the moderator) | ~1–2B | tutoring, Q&A, summaries, **authors explanations** | ⏳ |
| Specialized | — | OCR, vision, speech, embeddings | ⏳ |

---

## 12. Orchestration (the Moderator — the "real brain")

The decision loop (spec §33):

> What did they give me? → What are they asking? → What info do I need? →
> Which engine? → Internet? → AI? → What should the answer look like? → How to render?

Mapped to components (see `PATHWAY.md` §0):

| Spec question | Component |
|---|---|
| "What did they give me?" | Input engine |
| "What are they asking?" | Moderator (intent) |
| "Which engine / format?" | Moderator (decide) |
| "How to render?" | Moderator (assemble) |

---

## 13. Personalization

| Feature | Input | Output | Status |
|---|---|---|---|
| Track subjects, topics, weak areas, quiz performance, study history | activity events | labelled memory log | ⏳ |
| "Quiz me on what I struggled with yesterday" | query | quiz (from memory) | ⏳ |

---

## 14. Study Modes

`Learn`, `Solve`, `Research`, `Practice`, `Quiz`, `Revise`, `Create`, `Explore`

These are the `mode` values in the request shape (see `json.md` §2).

---

## 15. Voice (later phase)

| Feature | Input | Output | Status |
|---|---|---|---|
| Speech recognition → intent → knowledge → response → text + voice | audio | spoken answer | ⏳ |
| "Read this chapter to me" | text | speech | ⏳ |

---

## Build Priority (v1 core)

1. Math Engine (symbolic + graphing) — ✅
2. PDF Engine — ✅
3. OCR (text only) — ✅
4. Input Engine (classification) — ✅
5. Moderator (rule-based) — ✅
6. Block Renderer (text/equation/graph/quiz) — ✅ (Flutter, later)

Everything else: build when fun, or skip. This is a pet project — the queue is a menu.
