# Adaptive enhancement

> Status: ✅ core v1

- **Input:** image
- **Output:** deblur / denoise / sharpen / contrast / exposure / perspective-correct / deskew / crop

## JSON shape

Input: `{ "image": "<path to image file>", "quality": { "blur": 0.2, "noise": 0.1, "lighting": "dark" } }` (`quality` optional — computed via `image_processing/quality_analysis` if omitted)
Output: `{ "image": "<path to enhanced image file>", "applied": ["denoise", "perspective_correct", "crop", "sharpen", "contrast"] }`

## Notes

- Built on OpenCV. Reuses `image_processing/quality_analysis` (via `importlib`, same pattern as elsewhere in this project) for both quality metrics and its document-boundary contour detection — no duplicated contour-finding code.
- **Every step is conditional** — only applied if the image actually needs it (`blur > 0.5` -> sharpen, `noise > 0.3` -> denoise, `lighting != "ok"` -> contrast, a document boundary found -> perspective-correct + crop). `applied` reports exactly what ran.
- **Honesty note:** "deblur" from the original feature list is implemented as unsharp-mask **sharpening** (edge enhancement), not true deconvolution-based deblurring — that needs a known/estimated blur kernel and is a much harder inverse problem, not attempted. The applied-step name is `"sharpen"`, not `"deblur"`, so it doesn't overclaim.
- **`perspective_correct` subsumes `deskew`** — a proper 4-point perspective warp to a rectangle already straightens any rotation, so there's no separate rotate-only deskew step. Verified: a document rotated 12° and warped came back with `rotation: 0.0` when re-checked through `quality_analysis`.
- `contrast` uses CLAHE (contrast-limited adaptive histogram equalization) on the LAB lightness channel, not a flat brightness add — CLAHE expands local contrast without blowing out highlights/shadows the way a uniform brightness shift would.
- Output is written to `<original_stem>_enhanced<ext>` next to the source image.
- Tested end-to-end: fed a synthetic document image rotated 12°, the output was verified (by re-running `quality_analysis` on it) to have `rotation: 0.0`, `perspective: 0.0`, and a tighter crop (553x403 vs the original 800x600) — the correction demonstrably worked, not just "ran without error." A separately tested dark image correctly triggered `contrast` only.
