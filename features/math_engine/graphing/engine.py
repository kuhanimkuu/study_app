"""
Graphing — generates plot data/points for a single-variable expression.

INPUT (JSON) — what this engine receives:
{
    "expression": "x**2",
    "variable": "x",       // optional, default "x"
    "range": [-5, 5],
    "num_points": 200      // optional, default 200
}

OUTPUT (JSON) — what this engine returns:
{
    "points": {"x": [-5.0, -4.95, ...], "y": [25.0, 24.5, ...]},
    "latex": "y = x^2"
}

Points where the expression is undefined or non-finite (division by zero,
sqrt/log of a negative number, etc.) are silently dropped rather than
included as null/Infinity — Infinity isn't valid JSON, and a gap in the
plotted line is the mathematically honest way to show "undefined here"
(e.g. 1/x has no point at x=0).

Status: core v1
Built on sympy (parse + lambdify) + numpy (point evaluation). Returns raw
point data, not a rendered image — matches json.md's "interactive_graph"
block type, which expects data the frontend renders/interacts with, not a
static picture.
"""
from __future__ import annotations

from typing import Any

import numpy as np
import sympy
from sympy.parsing.sympy_parser import (
    implicit_multiplication_application,
    standard_transformations,
    parse_expr,
)

_TRANSFORMATIONS = standard_transformations + (implicit_multiplication_application,)


def _strip_lhs(expression: str) -> str:
    """"y = 3*x + 2" / "f(x) = x**2" -> "3*x + 2" / "x**2". This engine
    plots a single-variable function of `variable`, so a leading "y ="/
    "f(x) =" label — extremely common phrasing ("graph y = 3x + 2") — is
    just notation, not a second variable to solve for; sympy's parse_expr
    has no notion of "=" at all and previously raised a raw SyntaxError
    for exactly this input (real bug, found via a real device test, not
    theoretical). Only the first "=" is treated this way; a genuine
    multi-variable relation like "x + y = 5" was never supported by this
    single-variable plotter either way, so nothing is lost."""
    if "=" in expression:
        return expression.split("=", 1)[1].strip()
    return expression


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): {"expression": "...", "variable"?: str, "range": [lo, hi], "num_points"?: int}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    expression: str = _strip_lhs(kwargs["expression"])
    variable: str = kwargs.get("variable", "x")
    lower, upper = kwargs["range"]
    num_points: int = kwargs.get("num_points", 200)

    var = sympy.Symbol(variable)
    expr = parse_expr(expression, transformations=_TRANSFORMATIONS)
    f = sympy.lambdify(var, expr, modules=["numpy"])

    xs = np.linspace(lower, upper, num_points)
    with np.errstate(all="ignore"):
        ys = f(xs)
    ys = np.broadcast_to(np.asarray(ys, dtype=float), xs.shape)

    finite = np.isfinite(ys)
    x_list = xs[finite].tolist()
    y_list = ys[finite].tolist()

    return {"points": {"x": x_list, "y": y_list}, "latex": f"y = {sympy.latex(expr)}"}


if __name__ == "__main__":
    import asyncio

    def show(label: str, result: dict) -> None:
        pts = result["points"]
        enc = __import__("sys").stdout.encoding or "utf-8"
        print(f"--- {label} ---")
        print("latex:", result["latex"].encode(enc, errors="replace").decode(enc))
        print(f"points returned: {len(pts['x'])}")
        if pts["x"]:
            print(f"  first: ({pts['x'][0]:.3f}, {pts['y'][0]:.3f})")
            print(f"  last:  ({pts['x'][-1]:.3f}, {pts['y'][-1]:.3f})")

    async def demo() -> None:
        show("x**2 over [-5,5]", await run(expression="x**2", range=[-5, 5], num_points=11))
        show("1/x over [-5,5] (expect gap at x=0)", await run(expression="1/x", range=[-5, 5], num_points=11))
        show("sqrt(x) over [-5,5] (expect only x>=0)", await run(expression="sqrt(x)", range=[-5, 5], num_points=11))
        show("constant 5 over [-5,5]", await run(expression="5", range=[-5, 5], num_points=5))

    asyncio.run(demo())
