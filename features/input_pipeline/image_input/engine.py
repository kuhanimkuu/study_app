"""
Image input — accepts an image (camera/gallery/file/screenshot) and
normalizes it: validates it's a real, readable image and reports facts
about it. Does NOT run OCR or vision routing itself.

INPUT (JSON) — what the input layer receives:
{
    "content": "<path to image file>",
    "source": "camera"           # camera | gallery | file | screenshot
}

OUTPUT (JSON) — what this engine returns to the moderator:
{
    "input_type": "image",
    "content": "<image reference>",
    "detected": [],
    "metadata": {"source": "camera", "width": 1200, "height": 900, "format": "JPEG"}
}

"detected" stays empty here on purpose — real vision routing (deciding
whether this is printed text / handwriting / math / a graph / a diagram /
a photo / a table) is image_processing/content_identification's job, which
is a later-phase feature and not implemented yet. This engine only reports
facts it can get for free by opening the file: dimensions and format. Per
this project's division of labour, the input layer reports facts, never
meaning — pixel dimensions are a fact, "this is a photo of handwriting" is
meaning.

Status: core v1
Built on Pillow — just enough to open the file and read its basic
properties, no image processing.
"""
from __future__ import annotations

from typing import Any

from PIL import Image


async def run(**kwargs: Any) -> dict:
    """Sole entry point the input layer calls.

    Args (kwargs): {"content": "<path to image file>", "source"?: str}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    content: str = kwargs["content"]
    source: str = kwargs.get("source", "file")

    with Image.open(content) as img:
        width, height = img.size
        image_format = img.format

    return {
        "input_type": "image",
        "content": content,
        "detected": [],
        "metadata": {"source": source, "width": width, "height": height, "format": image_format},
    }


if __name__ == "__main__":
    import asyncio
    import sys

    image_path = sys.argv[1] if len(sys.argv) > 1 else None
    if not image_path:
        print(f"[{__name__}] usage: python engine.py <path-to-image>")
    else:
        result = asyncio.run(run(content=image_path, source="file"))
        print(result)
