"""Tests for the empty/None-content guards in features/model_router/engine.py
(2026-09-18) — both OpenAIBackend.generate and AnthropicBackend.generate
used to call .strip()/index into an empty response unconditionally,
crashing with AttributeError/IndexError instead of cleanly returning an
empty reply the caller (moderator/engine.py's _author_general_reply,
_author_text, _route_write_doc) already treats as "no answer, not a
failure." Found via deepseek-reasoner reliably returning
message.content=None at this app's token budgets (see
STUDY_OS_PROGRESS.md's 2026-09-18 entry).

Constructs each Backend via __new__ (bypassing __init__, which needs a
real SDK client/API key) and hands it a fake client whose response shape
matches the real SDK's, so this tests the exact code path without any
real network/API key.

Run with: python -m pytest server/tests/test_model_router_backends.py -v
"""
from __future__ import annotations

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
