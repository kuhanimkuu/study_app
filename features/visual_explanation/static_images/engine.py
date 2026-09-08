"""
Static images — generates a static image (PNG/JPEG/WebP) from data.

INPUT (JSON) — what this engine receives:
{
    "data": {"points": {"x": [...], "y": [...]}, "title": "y = x^2"},
    "format": "png",
    "output_path": "graph.png"      // optional
}

OUTPUT (JSON) — what this engine returns:
{
    "image": "<path to generated image file>",
    "format": "png"
}

Status: later phase
Built on matplotlib (headless "Agg" backend, appropriate for a server with
no display). A real render, not a placeholder file.
"""
from __future__ import annotations

from typing import Any

import matplotlib

matplotlib.use("Agg")  # headless — no display available/needed on a server
import matplotlib.pyplot as plt


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): {"data": {"points": {"x": [...], "y": [...]}, "title"?: str}, "format"?: str, "output_path"?: str}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    data: dict = kwargs["data"]
    image_format: str = kwargs.get("format", "png")
    output_path: str = kwargs.get("output_path", f"static_image.{image_format}")

    points = data["points"]
    title = data.get("title", "")

    fig, ax = plt.subplots(figsize=(6, 4))
    ax.plot(points["x"], points["y"])
    if title:
        ax.set_title(title)
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    fig.savefig(output_path, format=image_format)
    plt.close(fig)

    return {"image": output_path, "format": image_format}


if __name__ == "__main__":
    import asyncio
    from pathlib import Path

    async def demo() -> None:
        xs = [x * 0.1 for x in range(-50, 51)]
        ys = [x * x for x in xs]
        result = await run(data={"points": {"x": xs, "y": ys}, "title": "y = x^2"}, output_path="scratch_static_demo.png")
        path = Path(result["image"])
        print(result, "exists:", path.exists(), "size:", path.stat().st_size if path.exists() else 0)
        path.unlink(missing_ok=True)

    asyncio.run(demo())
