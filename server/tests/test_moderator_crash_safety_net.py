"""Tests the last-resort safety net in features/moderator/engine.py's
run() (2026-09-18) — added after fixing three real crashes in one session
that all shared the same shape: a bug anywhere in the routing tree (not a
specific sibling engine's own failure, which every _route_* function
already catches) propagating all the way up as an unhandled exception
instead of the {"blocks": [...]} shape every caller expects.

Deliberately simulates a genuinely unexpected bug (not NeedsClarification
or ModelUnavailable, which have their own dedicated, already-tested
handling) by monkeypatching `_route` itself — this isn't about any one
specific engine, it's the generic backstop.

Run with: python -m pytest server/tests/test_moderator_crash_safety_net.py -v
"""
from __future__ import annotations

import pytest

import features.moderator.engine as moderator_engine


@pytest.mark.asyncio
async def test_an_unexpected_bug_anywhere_in_routing_degrades_to_an_error_block_not_a_crash(monkeypatch):
    async def fake_route(*args: object, **kwargs: object) -> None:
        raise KeyError("simulated unexpected bug, not NeedsClarification/ModelUnavailable")

    monkeypatch.setattr(moderator_engine, "_route", fake_route)

    result = await moderator_engine.run(
        input_type="text",
        content="anything",
        model_config={"backend": "local", "tier": "tiny"},
        session_id="test-crash-safety-net",
    )

    assert result["blocks"] == [
        {
            "type": "error",
            "engine": "moderator",
            "message": "'simulated unexpected bug, not NeedsClarification/ModelUnavailable'",
        }
    ]
    assert result["session_id"] == "test-crash-safety-net"
