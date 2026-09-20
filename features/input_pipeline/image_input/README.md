# Image input

> Status: ✅ core v1

- **Input:** image bytes (camera / gallery / file / screenshot)
- **Output:** content (via OCR / vision)

## JSON shape

Input:
```json
{ "content": "<path to image file>", "source": "camera" }
```
`source` optional (`camera | gallery | file | screenshot`, default `"file"`).

Output:
```json
{ "input_type": "image", "content": "<image reference>", "detected": [], "metadata": { "source": "camera", "width": 1200, "height": 900, "format": "JPEG" } }
```

## Notes

- Does **not** run OCR or vision routing itself — `detected` stays empty on purpose. Real vision routing (printed text vs handwriting vs math vs graph vs diagram vs photo vs table) is `image_processing/content_identification`'s job, which is a later-phase feature and not implemented yet. This engine only reports facts it gets for free by opening the file: dimensions and format. Per this project's division of labour, the input layer reports facts, never meaning — pixel dimensions are a fact, "this is a photo of handwriting" is meaning.
- Built on Pillow — just opens the file and reads `.size`/`.format`, no processing.
- Tested against a synthetic 640x480 JPEG: correctly reported width/height/format.
