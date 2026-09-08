# Speech recognition

> Status: 🚫 out of scope for this repo — deliberate, not a lower-priority TODO

- **Input:** audio
- **Output:** spoken answer (speech → intent → knowledge → response → text + voice)

## Notes

**Decided not to build this as a Python engine, on purpose.** Even though the project moved to a server-hosted backend for the heavier engines (PDF/OCR/RAG — see `document_engine/scanned_ocr/README.md` for that research), voice specifically stays client-native: it needs low-latency, real-time interaction, and Android already provides a mature, free, on-device API for it — `android.speech.SpeechRecognizer` (confirmed during this session's Android capability research: "Basic Mode" works on most devices, API 31+; no server round-trip needed, no Chaquopy/Python involved at all). Round-tripping audio to a Python backend for basic transcription would be strictly worse UX for no real benefit.

If this ever needs revisiting: ML Kit's GenAI "Speech Recognition" API is the higher-quality alternative, but its "Advanced Mode" is Pixel-only — "Basic Mode" is the one to target for broad device support (see the target device, Redmi Note 13 Pro, per `study_os_overview-v2.pdf`).
