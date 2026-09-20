# Symbolic math

> Status: ✅ core v1

- **Input:** expression
- **Output:** symbolic answer + steps (arithmetic, algebra, calculus, differentiation, integration, equations, matrices)

## JSON shape

Input:
```json
{ "expression": "2*x + 3 = 7", "variable": "x", "operation": "solve" }
```
`variable` optional (default `"x"`). `operation` optional — inferred as `"solve"` if the expression contains `=`, else `"simplify"`. Explicit values: `solve`, `simplify`, `differentiate`, `integrate`, `matrix_det`, `matrix_inverse` (the last two take a `Matrix([[...]])`-style expression string instead of an algebraic one).

Output:
```json
{ "answer": "2", "latex": "x = 2", "steps": ["Move all terms to one side: 2x - 4 = 0", "Subtract 4 from both sides: 2x = 4", "Divide both sides by 2: x = 2"] }
```

## Notes

- Built on sympy. Uses `parse_expr` with implicit multiplication enabled, so `"2x"` parses the same as `"2*x"`.
- **Honesty note on `steps`:** real step-by-step derivation is only implemented for linear equations in one variable (`_linear_solve_steps`, degree-1 polynomials) — that's the common case and the one the original skeleton's example assumed. For anything else (nonlinear/quadratic equations, differentiate, integrate, matrix ops), `steps` contains one line stating what sympy computed, not a fabricated rule-by-rule derivation. This matches the project's existing pattern of saying "not implemented" rather than faking pedagogy (same idea as `pdf_processing`'s `"equations": []`).
- `integrate` always returns an indefinite integral and manually appends `+ C` (sympy itself omits the constant of integration).
- `operation` is not auto-inferred beyond solve/simplify — differentiate/integrate/matrix ops must be requested explicitly, since there's no reliable way to guess "integrate this" from a bare expression string. This will matter once the moderator is calling this engine and needs to pass `operation` based on detected intent.
- Errors (bad expression syntax, unknown `operation`, singular matrix on `matrix_inverse`, etc.) propagate as exceptions rather than being caught and wrapped here — same precedent as the other engines built so far; wrapping into the `{"status": "error", ...}` shape from `json.md` is treated as the moderator's job, not each engine's.
- Tested standalone (`python engine.py`) across all six operations: linear solve (`2x+3=7` → `x=2`), quadratic solve (`x²-5x+6=0` → `2, 3`, honest fallback steps), simplify (`(x²-1)/(x-1)` → `x+1`), differentiate (`x³+3x²` → `3x²+6x`), integrate (`2x` → `x²+C`), matrix determinant and inverse of `[[1,2],[3,4]]` — all correct.
