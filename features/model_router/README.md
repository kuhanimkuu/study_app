# Model router

> Status: ⏳ later phase

- **Input:** classified task
- **Output:** model selection

## Model tiers

| Model | Size | Job |
|---|---|---|
| Tiny model | ~0.3–0.6B | classification, routing, extraction |
| Main model (the moderator) | ~1–2B | tutoring, Q&A, summaries, **authors explanations** |
| Specialized | — | OCR, vision, speech, embeddings |

## JSON shape

This isn't a per-request "engine" with a fixed contract like the others — it's a generation utility other code (the moderator) calls directly.

Input: `{ "prompt": "...", "tier": "tiny", "max_tokens": 200 }` (`tier`/`max_tokens` optional, default `"tiny"`/200)
Output: `{ "text": "...", "tier": "tiny" }`

## Notes

**Backend choice, and why:** `llama-cpp-python` (the natural first choice, matching the original spec's llama.cpp mention) ships **no prebuilt wheels on PyPI** — source-only, and its build requires CMake, which isn't available in this environment. Rather than force a from-source build, this uses **PyTorch + `transformers`** instead, which has proper prebuilt wheels for this Python version and installed cleanly.

**Pluggable by design, per explicit direction:** `Backend` is a tiny protocol (`generate(prompt, max_tokens) -> str`). `TransformersBackend` is the concrete implementation now; a hosted-API backend matching the same protocol can be swapped in later as a straight substitution, not a rewrite.

**Model:** `"tiny"` tier defaults to `Qwen/Qwen2.5-0.5B-Instruct` — chosen because it sits exactly in this project's own `features.md` spec ("tiny model, ~0.3-0.6B, classification/routing/extraction"). `"main"` tier (`Qwen/Qwen2.5-1.5B-Instruct`, matching the `~1-2B` spec) is wired into the interface but **not downloaded automatically** — fetching a second, larger model wasn't done by default to keep initial setup light; pass `tier="main"` to trigger its download on first use.

- **Real bug found and fixed via testing:** `apply_chat_template(..., return_tensors="pt")` returns a `BatchEncoding` (dict-like) in this `transformers` version when `return_dict` is left at its default, not a raw tensor — passing that straight into `model.generate()` as a positional argument broke with `AttributeError` (it expected `.shape` on a tensor). Fixed by passing `return_dict=True` explicitly and calling `generate(**inputs, ...)`.
- Model inference is blocking/CPU-bound; `run()` executes it via `loop.run_in_executor` so it doesn't block the async event loop the rest of this project's engines share.
- Tested end-to-end: `"In one short sentence, what is entropy?"` produced a real, coherent, correct answer from the actual local model — `"Entropy quantifies the disorder or randomness in a system, reflecting its potential for further disordered states."` — not a canned/stubbed response.
