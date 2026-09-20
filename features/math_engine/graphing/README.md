# Graphing

> Status: ✅ core v1

- **Input:** expression
- **Output:** graph data / points

## JSON shape

Input:
```json
{ "expression": "x**2", "variable": "x", "range": [-5, 5], "num_points": 200 }
```
`variable` and `num_points` are optional (defaults `"x"`, 200).

Output:
```json
{ "points": { "x": [-5.0, -4.95, "..."], "y": [25.0, 24.5, "..."] }, "latex": "y = x^2" }
```

## Notes

- Built on sympy (parse + `lambdify`) + numpy (point evaluation). Returns raw point data, not a rendered image — matches `json.md`'s `interactive_graph` block type, which expects data the Flutter frontend renders/interacts with, not a static picture. (The original skeleton's note mentioning matplotlib was for a hypothetical image-backend approach; this implementation doesn't render anything.)
- Points where the expression is undefined or non-finite (division by zero, sqrt/log of a negative number, etc.) are **silently dropped**, not included as `null`/`Infinity` — `Infinity` isn't valid JSON, and a gap in the plotted line is the mathematically honest way to show "undefined here" (e.g. `1/x` correctly has no point at `x=0`).
- Constant expressions (no dependence on `variable`, e.g. `"5"`) are handled via `np.broadcast_to` — `sympy.lambdify` returns a bare scalar for these instead of an array, which would otherwise break the point-filtering logic.
- Tested standalone (`python engine.py`): `x**2` (full parabola), `1/x` (correctly drops the point at `x=0`), `sqrt(x)` (correctly drops the entire negative half, keeping only `x>=0`), and a constant expression (`"5"`, correctly broadcasts to a flat line) — all verified.
