"""
Model router — loads and runs the LLM that backs the moderator's real
"brain" (PATHWAY.md Phase 5), behind a pluggable backend interface so a
hosted API (BYOK — user's own key) can be swapped in per-request without
changing any caller.

This isn't a per-request "engine" with a fixed input/output contract like
the others — it's a generation utility other code calls directly.

INPUT (the run() kwargs):
{
    "prompt": "...",           // already-formatted prompt (chat template applied by the caller)
    "tier": "tiny",            // local backend only: "tiny" (~0.3-0.6B) | "main" (~1-2B)
    "backend": "local",        // "local" | "anthropic" | "openai"
    "api_key": null,           // required for "anthropic"/"openai" — the USER'S OWN key (BYOK)
    "model_name": null,        // optional override; sensible default per backend if omitted
    "max_tokens": 200          // optional
}

OUTPUT:
{ "text": "...", "tier": "tiny", "backend": "local" }

Status: later phase (this is the Phase 5 "real brain" piece)

Backend abstraction: `Backend` is a tiny protocol (`generate(prompt, max_tokens) -> str`).
`TransformersBackend` (local, cached — loading a model is expensive) is the
free default; `AnthropicBackend`/`OpenAIBackend` (hosted, NOT cached — see
below) are the BYOK options.

Why hosted backends are never cached as singletons, unlike the local one:
different users bring different API keys. A cached hosted-backend instance
keyed only by tier (the local backend's pattern) would leak one user's
client — and therefore effectively their key — into another user's request
if reused. Anthropic/OpenAI SDK client construction is cheap (no multi-
hundred-MB model to load), so a fresh client per call is the safe default,
not a performance compromise.

Model: local "tiny" tier defaults to Qwen2.5-0.5B-Instruct — chosen because
it sits exactly in features.md's own specified "~0.3-0.6B, classification/
routing/extraction" range. No local "main" tier model (~1-2B, per
features.md) is downloaded by default — the interface supports it (pass
tier="main"), but fetching a second, larger model wasn't done automatically
to keep initial setup light.
"""
from __future__ import annotations

import asyncio
from typing import Any, Protocol

TIER_MODELS = {
    "tiny": "Qwen/Qwen2.5-0.5B-Instruct",
    "main": "Qwen/Qwen2.5-1.5B-Instruct",  # not downloaded by default — see README
}
DEFAULT_MODEL_NAMES = {
    "anthropic": "claude-sonnet-5",
    "openai": "gpt-4o-mini",
}


class Backend(Protocol):
    def generate(self, prompt: str, max_tokens: int) -> str: ...


class TransformersBackend:
    """Runs a local Hugging Face model via `transformers`, CPU inference."""

    def __init__(self, model_id: str):
        from transformers import AutoModelForCausalLM, AutoTokenizer

        self._tokenizer = AutoTokenizer.from_pretrained(model_id)
        self._model = AutoModelForCausalLM.from_pretrained(model_id)

    def generate(self, prompt: str, max_tokens: int) -> str:
        import torch

        messages = [{"role": "user", "content": prompt}]
        # return_dict=True is required explicitly here: this transformers
        # version's apply_chat_template(..., return_tensors="pt") returns a
        # BatchEncoding (dict-like), not a raw tensor, when return_dict is
        # left at its default — passing that straight into model.generate()
        # as a positional arg breaks (generate() expects a tensor there).
        # Found by running this engine and reading the resulting traceback.
        inputs = self._tokenizer.apply_chat_template(
            messages, add_generation_prompt=True, return_dict=True, return_tensors="pt"
        )
        with torch.no_grad():
            output_ids = self._model.generate(
                **inputs,
                max_new_tokens=max_tokens,
                do_sample=True,
                temperature=0.4,
                pad_token_id=self._tokenizer.eos_token_id,
            )
        new_tokens = output_ids[0][inputs["input_ids"].shape[1] :]
        return self._tokenizer.decode(new_tokens, skip_special_tokens=True).strip()


class AnthropicBackend:
    """BYOK — the caller's own Anthropic API key, never this project's."""

    def __init__(self, api_key: str, model: str):
        import anthropic

        self._client = anthropic.Anthropic(api_key=api_key)
        self._model = model

    def generate(self, prompt: str, max_tokens: int) -> str:
        response = self._client.messages.create(
            model=self._model,
            max_tokens=max_tokens,
            messages=[{"role": "user", "content": prompt}],
        )
        return response.content[0].text.strip()


class OpenAIBackend:
    """BYOK — the caller's own OpenAI (or OpenAI-compatible) API key."""

    def __init__(self, api_key: str, model: str):
        import openai

        self._client = openai.OpenAI(api_key=api_key)
        self._model = model

    def generate(self, prompt: str, max_tokens: int) -> str:
        response = self._client.chat.completions.create(
            model=self._model,
            max_tokens=max_tokens,
            messages=[{"role": "user", "content": prompt}],
        )
        return response.choices[0].message.content.strip()


_local_backends: dict[str, Backend] = {}  # lazy singletons per tier — loading a model is expensive


def _get_backend(backend_name: str, tier: str, api_key: str | None, model_name: str | None) -> Backend:
    if backend_name == "local":
        if tier not in _local_backends:
            if tier not in TIER_MODELS:
                raise ValueError(f"unknown tier: {tier!r} (expected 'tiny' or 'main')")
            _local_backends[tier] = TransformersBackend(TIER_MODELS[tier])
        return _local_backends[tier]

    if backend_name in ("anthropic", "openai"):
        if not api_key:
            raise ValueError(f"backend={backend_name!r} requires an api_key (BYOK — the user's own key)")
        model = model_name or DEFAULT_MODEL_NAMES[backend_name]
        return AnthropicBackend(api_key, model) if backend_name == "anthropic" else OpenAIBackend(api_key, model)

    raise ValueError(f"unknown backend: {backend_name!r} (expected 'local', 'anthropic', or 'openai')")


async def run(**kwargs: Any) -> dict:
    """Sole entry point callers use.

    Args (kwargs): {"prompt": str, "tier"?: str, "backend"?: str, "api_key"?: str,
                     "model_name"?: str, "max_tokens"?: int}
    Returns: {"text": str, "tier": str, "backend": str} — always JSON-serializable.
    """
    prompt: str = kwargs["prompt"]
    tier: str = kwargs.get("tier", "tiny")
    backend_name: str = kwargs.get("backend", "local")
    api_key: str | None = kwargs.get("api_key")
    model_name: str | None = kwargs.get("model_name")
    max_tokens: int = kwargs.get("max_tokens", 200)

    backend = _get_backend(backend_name, tier, api_key, model_name)
    loop = asyncio.get_event_loop()
    # generate() is a blocking call (local: CPU-bound model inference;
    # hosted: a synchronous SDK network call) — run it off the event loop
    # so this coroutine doesn't block the whole async moderator/scheduler
    text = await loop.run_in_executor(None, backend.generate, prompt, max_tokens)

    return {"text": text, "tier": tier, "backend": backend_name}


if __name__ == "__main__":
    import asyncio as _asyncio

    async def demo() -> None:
        result = await run(prompt="In one short sentence, what is entropy?", max_tokens=60)
        print("backend:", result["backend"], "tier:", result["tier"])
        print("text:", result["text"])

    _asyncio.run(demo())
