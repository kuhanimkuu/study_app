"""
Text input — accepts a typed string and normalizes it for the moderator.

INPUT (JSON) — what the input layer receives:
{
    "content": "2x + 3 = 7",   # the typed string
    "source": "text"           # origin: text
}

OUTPUT (JSON) — what this engine returns to the moderator:
{
    "input_type": "text",
    "content": "2x + 3 = 7",
    "detected": ["math"]
}

"detected" is a cheap regex heuristic (does this look like it contains a
math expression?), not real understanding — that stays the moderator's job
per this project's division of labour. It's an addition beyond the original
skeleton's bare {"input_type", "content"} output, made for symmetry with
image_input's own skeleton (which already had "detected") and because it's
a genuine, free fact about the text, not a guess at meaning.

Status: core v1
"""
from __future__ import annotations

import re
from typing import Any

_MATH_HINT_RE = re.compile(
    r"\d\s*[+\-*/^=]\s*\d"          # e.g. "2 + 3", "2x=7" (digit, operator, digit)
    r"|[a-zA-Z]\s*=\s*[\d\-]"        # e.g. "x = 5"
    r"|\d\s+(plus|minus|times|divided by|equals)\s+\d"  # spoken-math, e.g. from audio_input's transcription
    r"|\b(sin|cos|tan|log|ln|sqrt|integral|derivative|matrix)\b",
    re.IGNORECASE,
)


async def run(**kwargs: Any) -> dict:
    """Sole entry point the input layer calls.

    Args (kwargs): {"content": "...", "source"?: str}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    content: str = kwargs["content"].strip()
    detected = ["math"] if _MATH_HINT_RE.search(content) else []
    return {"input_type": "text", "content": content, "detected": detected}


if __name__ == "__main__":
    import asyncio

    async def demo() -> None:
        for sample in ["2x + 3 = 7", "explain the second law of thermodynamics", "  what is sin(x)?  "]:
            result = await run(content=sample)
            print(result)

    asyncio.run(demo())
