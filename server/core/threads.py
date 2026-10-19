"""
Runs a features/ engine off the server's event loop.

Most engines are `async def` with fully synchronous bodies (PDF parsing,
OCR, Whisper, sympy, matplotlib, blocking `requests` calls) — awaited
directly, one of them freezes every other request and Render's health
check until it finishes. This was a private helper in
domains/knowledge/router.py; it moved here (2026-10-19) so routers/ask.py
and the other HTTP routes share it.

It delegates to the moderator's own `run_in_thread`, so the HTTP layer and
the moderator draw from ONE small worker pool — two pools would let twice as
many memory-heavy jobs run at once on a 512 MB instance. (features/ can't
import server/, so the pool has to live on the moderator's side.)
"""
from __future__ import annotations

from types import ModuleType
from typing import Any

from .. import engines


async def run_engine_in_thread(engine: ModuleType, **kwargs: Any) -> dict:
    """`await run_engine_in_thread(engines.pdf_input, content=path)` in
    place of `await engines.pdf_input.run(content=path)`."""
    return await engines.moderator.run_in_thread(engine, **kwargs)
