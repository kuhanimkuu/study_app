"""
Diagrams — generates a structured/editable diagram from data (positions +
connections for a frontend to render and let the user edit — NOT a flat
picture; that's visual_explanation/static_images' job).

INPUT (JSON) — what this engine receives:
{
    "data": {
        "kind": "circuit",
        "elements": ["battery", "resistor", "capacitor"],
        "relationships": [[0, 1], [1, 2]]    // optional, pairs of element indices that connect
    }
}

OUTPUT (JSON) — what this engine returns:
{
    "diagram": {
        "kind": "circuit",
        "elements": [
            {"id": 0, "label": "battery", "x": 0, "y": 0},
            {"id": 1, "label": "resistor", "x": 150, "y": 0}
        ],
        "relationships": [[0, 1], [1, 2]]
    }
}

Status: later phase

HONESTY NOTE: layout is a simple, real auto-layout — elements placed in a
left-to-right row, wrapping to a new row every 4 elements. This is NOT a
smart graph-layout algorithm (no force-directed placement, no
relationship-aware positioning) — a real diagram-layout library (e.g.
graphviz) would do meaningfully better, especially for anything with
non-linear relationships. If `relationships` isn't given in the input,
it defaults to a simple sequential chain (element i connects to i+1) as a
reasonable default for a linear diagram like a basic flowchart/circuit —
not inferred from any real understanding of what the elements are.
"""
from __future__ import annotations

from typing import Any

ROW_WIDTH = 4
X_SPACING = 150
Y_SPACING = 120


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): {"data": {"kind": str, "elements": list[str], "relationships"?: list[list[int]]}}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    data: dict = kwargs["data"]
    kind: str = data.get("kind", "unknown")
    element_labels: list[str] = data.get("elements", [])
    relationships: list[list[int]] | None = data.get("relationships")

    elements = [
        {
            "id": i,
            "label": label,
            "x": (i % ROW_WIDTH) * X_SPACING,
            "y": (i // ROW_WIDTH) * Y_SPACING,
        }
        for i, label in enumerate(element_labels)
    ]

    if relationships is None:
        relationships = [[i, i + 1] for i in range(len(element_labels) - 1)]

    return {"diagram": {"kind": kind, "elements": elements, "relationships": relationships}}


if __name__ == "__main__":
    import asyncio

    async def demo() -> None:
        result = await run(data={"kind": "circuit", "elements": ["battery", "resistor", "capacitor", "led", "switch"]})
        for el in result["diagram"]["elements"]:
            print(el)
        print("relationships:", result["diagram"]["relationships"])

    asyncio.run(demo())
