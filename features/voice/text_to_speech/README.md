# Text-to-speech

> Status: 🚫 out of scope for this repo — deliberate, not a lower-priority TODO

- **Input:** text
- **Output:** speech ("read this chapter to me")

## Notes

**Decided not to build this as a Python engine, on purpose** — same reasoning as `voice/speech_recognition`. Android provides `android.speech.tts.TextToSpeech` natively: free, on-device, universal, zero server round-trip. There's no reason to generate audio server-side and stream it back when the OS already synthesizes speech locally.
