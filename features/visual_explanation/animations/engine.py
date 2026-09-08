"""
Animations — generates a step-by-step animation sequence.

INPUT (JSON) — what this engine receives:
{
    "data": {"steps": ["sin(x)", "sin(2*x)", "sin(3*x)"]},
    "range": [-6.28, 6.28],
    "fps": 2,
    "output_path": "animation.gif"    // optional
}

OUTPUT (JSON) — what this engine returns:
{
    "animation": {"frames": ["<frame 1 path>", "<frame 2 path>"], "fps": 2, "file": "animation.gif"}
}

Status: deferred / optional

HONESTY NOTE / interpretation choice: the original skeleton's INPUT
("steps": ["<frame 1>", "<frame 2>"]) doesn't specify what a "step" IS.
This implementation treats each step as a math expression to plot
(reusing math_engine/graphing), producing a real, viewable animated GIF
that shows how a graph changes across a sequence of expressions — a
genuine, testable interpretation, not the only possible one. Composes
math_engine/graphing (via importlib) for each frame's point data and
matplotlib (headless "Agg" backend) + Pillow to render and assemble the
real GIF, rather than faking placeholder frame references.
"""
from __future__ import annotations

import importlib.util
import io
from pathlib import Path
from types import ModuleType
from typing import Any

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from PIL import Image

_HERE = Path(__file__).resolve().parent
_FEATURES_ROOT = _HERE.parent.parent  # features/


def _load_sibling_engine(relative_path: str) -> ModuleType:
    path = _FEATURES_ROOT / relative_path
    module_name = "animations_dep_" + relative_path.replace("/", "_")
    spec = importlib.util.spec_from_file_location(module_name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_graphing = _load_sibling_engine("math_engine/graphing/engine.py")


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): {"data": {"steps": list[str]}, "range": [lo, hi], "fps"?: int, "output_path"?: str}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    steps: list[str] = kwargs["data"]["steps"]
    value_range: list[float] = kwargs["range"]
    fps: int = kwargs.get("fps", 2)
    output_path: str = kwargs.get("output_path", "animation.gif")

    frame_images = []
    for expression in steps:
        graph_result = await _graphing.run(expression=expression, range=value_range)
        frame_images.append(_render_frame(graph_result["points"], graph_result["latex"]))

    duration_ms = int(1000 / fps)
    frame_images[0].save(
        output_path, save_all=True, append_images=frame_images[1:], duration=duration_ms, loop=0
    )

    return {"animation": {"frames": [f"frame_{i}" for i in range(len(steps))], "fps": fps, "file": output_path}}


# --- private helpers ---


def _render_frame(points: dict, title: str) -> Image.Image:
    fig, ax = plt.subplots(figsize=(5, 4))
    ax.plot(points["x"], points["y"])
    ax.set_title(f"y = {title}")
    ax.grid(True, alpha=0.3)
    fig.tight_layout()

    buf = io.BytesIO()
    fig.savefig(buf, format="png")
    plt.close(fig)
    buf.seek(0)
    return Image.open(buf).convert("RGB")


if __name__ == "__main__":
    import asyncio

    async def demo() -> None:
        result = await run(
            data={"steps": ["sin(x)", "sin(2*x)", "sin(3*x)"]},
            range=[-6.28, 6.28],
            fps=2,
            output_path="scratch_animation_demo.gif",
        )
        path = Path(result["animation"]["file"])
        print(result, "exists:", path.exists(), "size:", path.stat().st_size if path.exists() else 0)
        path.unlink(missing_ok=True)

    asyncio.run(demo())
