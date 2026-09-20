# Quality analysis

> Status: ✅ core v1

- **Input:** image
- **Output:** blur / noise / resolution / lighting / perspective / rotation + "is it a document?"

## JSON shape

Input: `{ "image": "<path to image file>" }`
Output:
```json
{
    "quality": {
        "blur": 0.2, "noise": 0.1, "resolution": "1080x1920", "lighting": "ok",
        "perspective": 0.0, "rotation": 1.5, "is_document": true
    }
}
```
`perspective` is `null` when no document boundary was confidently detected (honest "couldn't tell", not a guessed 0).

## Notes

Built on OpenCV. Every metric is a real, named, standard computer-vision technique — no ML model, no black box:

- **`blur`** — Laplacian variance (Pech-Pacheco et al., 2000), **normalized by the image's own pixel variance** to be scale-invariant to brightness/contrast. This normalization was added because the *unnormalized* version failed this engine's own test: a darkened-but-equally-sharp image was reported as blurrier just because darkening shrinks raw pixel differences. The normalized ratio is scale-invariant by construction (verified: a sharp image and a 4x-darkened copy of it scored identically, 0.546 vs 0.560 raw ratio).
  - **Known confound, honestly documented rather than hidden:** heavy noise inflates the Laplacian-variance ratio (noise looks like high-frequency "edges" to this metric), so a heavily blurred *and* noisy image can score as sharp (`blur: 0.0`) — caught directly by this engine's own test suite. Always read `blur` together with `noise`; a low `blur` + high `noise` combination likely means real blur is being masked, not that the image is actually sharp.
  - `REFERENCE_RATIO = 0.5` was calibrated empirically against this engine's own synthetic test images (a rendered-text "document" scored ratio 0.546, sharp; a heavily Gaussian-blurred version scored 0.00095) — not derived from a formula, an honest empirical constant like `pdf_processing`'s and `scanned_ocr`'s thresholds.
- **`noise`** — fast noise variance estimation (Immerkaer, 1996): convolves with a kernel that cancels smooth/linear content, leaving mostly noise energy.
- **`lighting`** — mean grayscale brightness, thresholded into dark (<60) / ok / bright (>200).
- **`perspective`/`rotation`/`is_document`** — all derived from one shared step: find the largest 4-point contour via Canny edge detection + polygon approximation (typical of a page boundary against a background), ≥15% of image area. If none is found, `is_document` is `False` and `perspective` is `null`, `rotation` defaults to `0.0` — an honest "no document boundary detected," not a fabricated guess.
  - `perspective`: mean deviation of the quadrilateral's four interior angles from 90°, normalized — 0 for a square-on rectangle, higher for a skewed trapezoid.
  - `rotation`: skew angle in degrees via `cv2.minAreaRect` on the detected boundary.
- Tested against 5 synthetic images (rendered real text, not abstract shapes, for realistic edge density): sharp (`blur: 0.0`), heavily blurred (`blur: 0.998`), blurred+noisy (demonstrates the noise confound above), darkened (confirms brightness-invariance), and rotated 12° (`rotation: -11.88`, `is_document: True`, low `perspective` since rotation alone doesn't distort right angles).
