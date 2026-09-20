# Text question

> Status: ✅ core v1

- **Input:** typed string
- **Output:** content → moderator

## JSON shape

Input:
```json
{ "content": "2x + 3 = 7", "source": "text" }
```

Output:
```json
{ "input_type": "text", "content": "2x + 3 = 7", "detected": ["math"] }
```
`detected` is an addition beyond the original skeleton's bare `{"input_type", "content"}` — a cheap regex heuristic for "does this look like it contains math", not real understanding (that's the moderator's job). Added for symmetry with `image_input`'s own skeleton, which already had `detected`.

## Notes

- No external dependencies — just `.strip()` + a regex heuristic (`_MATH_HINT_RE`: digit-operator-digit patterns, `var = value` patterns, or common math function names like `sin`/`sqrt`/`integral`).
- Tested standalone: `"2x + 3 = 7"` and `"what is sin(x)?"` correctly flagged `["math"]`; `"explain the second law of thermodynamics"` correctly flagged `[]`.
