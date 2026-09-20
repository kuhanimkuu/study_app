"""
Interactive 2D — packages data for an interactive 2D visual (SVG/canvas/
native chart widget) on the frontend. The actual interactivity (hover/zoom/
pan) is a rendering concern for whatever renders this JSON — this engine's
real job is just producing correctly-shaped, real point data for it to
render, either passed through directly or computed from an expression.

INPUT (JSON) — what this engine receives, ONE of:
{ "data": { "points": { "x": [...], "y": [...] } } }
{ "expression": "sin(x)", "range": [-10, 10] }   // delegates to math_engine/graphing

OUTPUT (JSON) — what this engine returns:
{
    "visual": {"type": "2d", "data": {"points": {"x": [...], "y": [...]}}, "interactive": true}
}

Status: later phase
Composes math_engine/graphing (loaded via importlib, same pattern used
throughout this project) when given an expression rather than raw points,
instead of duplicating point-generation logic.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType
from typing import Any

_HERE = Path(__file__).resolve().parent
_FEATURES_ROOT = _HERE.parent.parent  # features/


def _load_sibling_engine(relative_path: str) -> ModuleType:
    path = _FEATURES_ROOT / relative_path
    module_name = "interactive_2d_dep_" + relative_path.replace("/", "_")
    spec = importlib.util.spec_from_file_location(module_name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_graphing = _load_sibling_engine("math_engine/graphing/engine.py")


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): either {"data": {"points": {...}}} or {"expression": str, "range": [lo, hi]}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    if "expression" in kwargs:
        graph_result = await _graphing.run(expression=kwargs["expression"], range=kwargs["range"])
        points = graph_result["points"]
    else:
        points = kwargs["data"]["points"]

    return {"visual": {"type": "2d", "data": {"points": points}, "interactive": True}}


if __name__ == "__main__":
    import asyncio

    async def demo() -> None:
        result = await run(expression="sin(x)", range=[-6.28, 6.28])
        print("points:", len(result["visual"]["data"]["points"]["x"]))
        print("interactive:", result["visual"]["interactive"])

    asyncio.run(demo())
