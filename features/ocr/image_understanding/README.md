# Image understanding

> Status: 🚫 deferred

- **Input:** image
- **Output:** description / semantics

## JSON shape

Input: `{ "image": "<path to image file>" }`
Output: `{ "description": "A 1200x900 image, mostly blue tones, bright lighting, simple composition. No readable text detected." }`

## Notes

**This is not image captioning — the most important caveat in this whole project.** "A photo of a bridge under tension" (the original feature's own example) needs a real vision-language model (BLIP, CLIP+LLM, or ML Kit's GenAI "Image Description" API — confirmed during this project's Android research to be Gemini-Nano-backed and flagship-device-only, unusable on the target Redmi Note 13 Pro). None of that is installed here — a multi-GB model dependency for a feature `features.md` itself marks 🚫 deferred/optional wasn't justified.

Instead, this builds a template sentence from real, measurable pixel facts already computable elsewhere in this project: dimensions, dominant color (nearest-match against a small named-color table), brightness, edge-density as a rough simple/busy proxy, and OCR text via `ocr/text_ocr` if any is found. **It describes measurable properties of the pixels, not what the image depicts or means.** Calling this "understanding" at all is generous — it's implemented because the task was to attempt every remaining feature best-effort, not because this is a real solution to the feature as originally described.

Tested against a synthetic bluish image with rendered text: correctly reported `400x300`, `"blue"` (matched the actual fill color), `"moderate"` lighting, `"simple"` composition, and correctly OCR'd `"Hello World"`.
