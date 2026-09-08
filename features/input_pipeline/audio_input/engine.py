"""
Audio input — accepts a spoken-audio FILE and transcribes it.

INPUT (JSON) — what the input layer receives:
{
    "content": "<path to audio file>"
}

OUTPUT (JSON) — what this engine returns to the moderator:
{
    "input_type": "text",
    "content": "transcribed question..."
}

Status: later phase

Scope note, reconciling this with the voice/* decision: this session
decided real-time voice interaction (speech_recognition, text_to_speech)
stays client-native (Android's SpeechRecognizer/TextToSpeech) — low
latency matters for a live conversation, and the OS already provides it
for free. This engine is a genuinely different case: transcribing an
already-recorded audio FILE the user uploads (e.g. "here's a recording of
my lecture, pull out the text") is not latency-sensitive, so server-side
transcription is the right call here, not a contradiction of that decision.

Built on faster-whisper (CTranslate2-based Whisper — no PyTorch dependency,
much lighter than openai-whisper) using the "tiny" model. Real transcription,
not a stub — but "tiny" trades accuracy for speed/size; a production
deployment would likely use a larger model.
"""
from __future__ import annotations

from typing import Any

from faster_whisper import WhisperModel

_model: WhisperModel | None = None  # lazy singleton — loading it is expensive


def _get_model() -> WhisperModel:
    global _model
    if _model is None:
        _model = WhisperModel("tiny", device="cpu", compute_type="int8")
    return _model


async def run(**kwargs: Any) -> dict:
    """Sole entry point the input layer calls.

    Args (kwargs): {"content": "<path to audio file>"}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    audio_path: str = kwargs["content"]
    model = _get_model()
    segments, _info = model.transcribe(audio_path)
    text = " ".join(segment.text.strip() for segment in segments).strip()
    return {"input_type": "text", "content": text}


if __name__ == "__main__":
    import asyncio
    import sys

    audio_path = sys.argv[1] if len(sys.argv) > 1 else None
    if not audio_path:
        print(f"[{__name__}] usage: python engine.py <path-to-audio-file>")
    else:
        result = asyncio.run(run(content=audio_path))
        print(result)
