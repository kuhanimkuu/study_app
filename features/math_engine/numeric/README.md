# Numeric math

> Status: ✅ core v1

- **Input:** expression
- **Output:** numeric answer (numerical methods, statistics, probability)

## JSON shape

Input shape depends on `operation` (replaces the original skeleton's vague `"method": "numeric"` field with an explicit dispatch, same pattern as `math_engine/symbolic`'s `operation`):

```json
{ "operation": "integrate", "expression": "sin(x)", "variable": "x", "bounds": [0, 3.14159265] }
{ "operation": "differentiate", "expression": "x**2", "variable": "x", "point": 3.0 }
{ "operation": "root", "expression": "x**2 - 4", "variable": "x", "bounds": [0, 3] }
{ "operation": "root", "expression": "x**2 - 4", "variable": "x", "point": 1.5 }
{ "operation": "stats", "data": [2, 4, 4, 4, 5, 5, 7, 9] }
{ "operation": "probability", "distribution": "normal", "params": {"mean": 0, "std": 1, "x": 1.96} }
{ "operation": "probability", "distribution": "binomial", "params": {"n": 10, "p": 0.5, "k": 5} }
```

Output:
```json
{ "answer": 2.0, "latex": "\\int_0^\\pi \\sin(x)\\,dx \\approx 2" }
```
`answer` is a float for `integrate`/`differentiate`/`root`, or a dict of named values for `stats`/`probability` (a single number doesn't fit those — e.g. `{"pdf": ..., "cdf": ...}`).

## Notes

- Built on numpy + scipy. sympy is used only to parse the expression string and `lambdify` it into a fast numeric function — the actual computation is genuinely numerical (scipy quadrature, Brent's method / Newton's method, finite differences), not sympy evaluated at a point. That's the real distinction from `math_engine/symbolic`.
- `differentiate` uses central finite-difference (`(f(x+h)-f(x-h))/(2h)`, `h=1e-6`) — an approximation, not exact, by design (this is the *numeric* engine; exact derivatives are `math_engine/symbolic`'s job).
- `root`: pass `bounds` for a bracketing method (`scipy.optimize.brentq`, requires a sign change between the two bounds) or `point` for Newton's method from an initial guess. At least one is required.
- `stats` uses Python's built-in `statistics` module (sample variance/stdev, `n-1` denominator) rather than numpy's population versions — flagged here since the two disagree for small `n`.
- `probability` currently supports `normal` (pdf + cdf at `x`) and `binomial` (pmf + cdf at `k`) via `scipy.stats`. Other distributions raise `ValueError` rather than silently guessing.
- Errors (missing bounds/point for `root`, unknown `operation`/`distribution`, bad expression syntax) propagate as exceptions — same precedent as every other engine built so far.
- Tested standalone (`python engine.py`) against known-correct values: ∫₀^π sin(x)dx = 2, d/dx[x²] at x=3 ≈ 6, root of x²-4 on [0,3] = 2, standard normal CDF(1.96) ≈ 0.975, Binomial(10, 0.5) pmf at k=5 ≈ 0.2461 — all matched.
