"""Tests for features/model_router/engine.py.

Part 1: the empty/None-content guards (2026-09-18) — both
OpenAIBackend.generate and AnthropicBackend.generate used to call
.strip()/index into an empty response unconditionally, crashing with
AttributeError/IndexError instead of cleanly returning an empty reply the
caller (moderator/engine.py's _author_general_reply, _author_text,
_route_write_doc) already treats as "no answer, not a failure." Found via
deepseek-reasoner reliably returning message.content=None at this app's
token budgets (see STUDY_OS_PROGRESS.md's 2026-09-18 entry).

Constructs each Backend via __new__ (bypassing __init__, which needs a
real SDK client/API key) and hands it a fake client whose response shape
matches the real SDK's, so this tests the exact code path without any
real network/API key.

Part 2 (2026-09-19): the local-model concurrency semaphore added after a
user question about real RAM/CPU usage under load (see
STUDY_OS_PROGRESS.md's matching entry) — PyTorch's default thread pool
tries to use every core for one generate() call, so unbounded concurrent
local-model requests contend rather than scale. These tests use a fake
"local" backend pre-seeded into the module's cache (no real model load —
that stays a separate, slower live-server verification, same discipline
as this project's other local-model changes) to prove the semaphore
actually serializes overlapping calls, and that it doesn't reach into
hosted BYOK traffic it has nothing to do with.

Run with: python -m pytest server/tests/test_model_router_backends.py -v
"""
from __future__ import annotations

import asyncio
import time

import features.model_router.engine as model_router_engine


class _FakeOpenAIMessage:
    def __init__(self, content: str | None) -> None:
        self.content = content


class _FakeOpenAIChoice:
    def __init__(self, content: str | None) -> None:
        self.message = _FakeOpenAIMessage(content)


class _FakeOpenAIResponse:
    def __init__(self, content: str | None) -> None:
        self.choices = [_FakeOpenAIChoice(content)]


class _FakeOpenAICompletions:
    def __init__(self, content: str | None) -> None:
        self._content = content

    def create(self, **kwargs: object) -> _FakeOpenAIResponse:
        return _FakeOpenAIResponse(self._content)


class _FakeOpenAIChat:
    def __init__(self, content: str | None) -> None:
        self.completions = _FakeOpenAICompletions(content)


class _FakeOpenAIClient:
    def __init__(self, content: str | None) -> None:
        self.chat = _FakeOpenAIChat(content)


def _openai_backend(content: str | None) -> model_router_engine.OpenAIBackend:
    backend = model_router_engine.OpenAIBackend.__new__(model_router_engine.OpenAIBackend)
    backend._client = _FakeOpenAIClient(content)
    backend._model = "deepseek-reasoner"
    return backend


def test_openai_backend_handles_none_content_without_crashing():
    backend = _openai_backend(None)
    assert backend.generate("hi", 50) == ""


def test_openai_backend_still_returns_real_text_normally():
    backend = _openai_backend("  a real reply  ")
    assert backend.generate("hi", 50) == "a real reply"


class _FakeAnthropicResponse:
    def __init__(self, content_blocks: list) -> None:
        self.content = content_blocks


class _FakeAnthropicMessages:
    def __init__(self, content_blocks: list) -> None:
        self._content_blocks = content_blocks

    def create(self, **kwargs: object) -> _FakeAnthropicResponse:
        return _FakeAnthropicResponse(self._content_blocks)


class _FakeAnthropicClient:
    def __init__(self, content_blocks: list) -> None:
        self.messages = _FakeAnthropicMessages(content_blocks)


class _FakeAnthropicTextBlock:
    def __init__(self, text: str) -> None:
        self.text = text


def _anthropic_backend(content_blocks: list) -> model_router_engine.AnthropicBackend:
    backend = model_router_engine.AnthropicBackend.__new__(model_router_engine.AnthropicBackend)
    backend._client = _FakeAnthropicClient(content_blocks)
    backend._model = "claude-sonnet-5"
    return backend


def test_anthropic_backend_handles_empty_content_list_without_crashing():
    backend = _anthropic_backend([])
    assert backend.generate("hi", 50) == ""


def test_anthropic_backend_still_returns_real_text_normally():
    backend = _anthropic_backend([_FakeAnthropicTextBlock("  a real reply  ")])
    assert backend.generate("hi", 50) == "a real reply"


class _SlowFakeLocalBackend:
    """Records how many concurrent `generate()` calls were in flight at
    once — the actual thing the semaphore is supposed to prevent from
    exceeding 1 (the default `LOCAL_MODEL_MAX_CONCURRENCY`)."""

    def __init__(self) -> None:
        self.active = 0
        self.max_active_seen = 0

    def generate(self, prompt: str, max_tokens: int) -> str:
        self.active += 1
        self.max_active_seen = max(self.max_active_seen, self.active)
        time.sleep(0.2)
        self.active -= 1
        return "local-ok"


async def test_concurrent_local_requests_are_serialized_by_the_semaphore(monkeypatch):
    fake = _SlowFakeLocalBackend()
    monkeypatch.setitem(model_router_engine._local_backends, "tiny", fake)
    monkeypatch.setattr(model_router_engine, "_LOCAL_GENERATION_SEMAPHORE", asyncio.Semaphore(1))

    results = await asyncio.gather(
        model_router_engine.run(prompt="a", backend="local", tier="tiny"),
        model_router_engine.run(prompt="b", backend="local", tier="tiny"),
    )

    assert [r["text"] for r in results] == ["local-ok", "local-ok"]
    assert fake.max_active_seen == 1, "both local generate() calls ran at once — the semaphore didn't serialize them"


async def test_hosted_backend_is_not_blocked_by_the_local_semaphore(monkeypatch):
    fake_local = _SlowFakeLocalBackend()
    monkeypatch.setitem(model_router_engine._local_backends, "tiny", fake_local)
    monkeypatch.setattr(model_router_engine, "_LOCAL_GENERATION_SEMAPHORE", asyncio.Semaphore(1))
    # Fake both __init__ and generate — constructing a *real* openai.OpenAI
    # client turned out to be slow enough in this environment (well over a
    # second, unrelated to anything under test here) to swamp the timing
    # assertion below with noise that has nothing to do with the
    # semaphore. Faking construction too isolates the measurement to
    # exactly what this test cares about.
    monkeypatch.setattr(model_router_engine.OpenAIBackend, "__init__", lambda self, *a, **kw: None)
    monkeypatch.setattr(model_router_engine.OpenAIBackend, "generate", lambda self, prompt, max_tokens: "hosted-ok")

    local_task = asyncio.create_task(model_router_engine.run(prompt="a", backend="local", tier="tiny"))
    await asyncio.sleep(0.02)  # let the local call acquire the semaphore and start its 0.2s "generation" first

    start = time.monotonic()
    hosted_result = await model_router_engine.run(prompt="b", backend="openai", api_key="sk-fake-test-key")
    hosted_elapsed = time.monotonic() - start
    await local_task

    assert hosted_result["text"] == "hosted-ok"
    assert hosted_elapsed < 0.15, "hosted call waited behind the local semaphore — it shouldn't have to"
