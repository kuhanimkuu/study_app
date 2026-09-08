# Audio input

> Status: ⏳ later phase

- **Input:** voice (spoken question)
- **Output:** text (via ASR)

## JSON shape

Input: `{ "content": "<path to audio file>" }`
Output: `{ "input_type": "text", "content": "transcribed question..." }`

## Notes

- **Reconciling this with the `voice/*` decision:** real-time voice interaction (`voice/speech_recognition`, `voice/text_to_speech`) stays client-native (Android's `SpeechRecognizer`/`TextToSpeech`) — low latency matters for a live conversation, and the OS already provides it for free. This engine is a genuinely different case: transcribing an already-recorded audio *file* the user uploads isn't latency-sensitive, so server-side transcription is the right call here, not a contradiction of that decision.
- Built on `faster-whisper` (CTranslate2-based Whisper, no PyTorch dependency) using the `"tiny"` model — real transcription, not a stub, but `"tiny"` trades accuracy for speed/size; a production deployment would likely use a larger model.
- Tested against a real generated speech clip (offline TTS via `pyttsx3`, not a scripted fake): spoken "Solve two x plus three equals seven" transcribed to `"Sol 2x plus 3 equals 7."` — correctly captured the mathematical content (Whisper even normalized number words to digits) with a minor word-clipping, a realistic result for the `"tiny"` model.
