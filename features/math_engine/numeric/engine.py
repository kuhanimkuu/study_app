"""
Numeric math — numerical methods, statistics, probability.

INPUT (JSON) — what this engine receives (shape depends on "operation"):
{
    "operation": "integrate",        // integrate | differentiate | root | stats | probability
    "expression": "sin(x)",          // for integrate/differentiate/root (sympy-syntax, evaluated numerically)
    "variable": "x",                 // optional, default "x"
    "bounds": [0, 3.14159265],       // integrate: [lower, upper]; root: bracket [a, b]
    "point": 1.0,                    // differentiate: point of evaluation; root: initial guess (if no bounds)
    "data": [1, 2, 3, 4, 5],         // stats
    "distribution": "normal",        // probability: normal | binomial
    "params": {"mean": 0, "std": 1, "x": 1.5}   // probability: distribution-specific
}

OUTPUT (JSON) — what this engine returns:
{ "answer": 2.0, "latex": "\\int_0^\\pi \\sin(x)\\,dx \\approx 2.0" }

"answer" is a float for integrate/differentiate/root, or a dict of named
values for stats/probability (a single named number doesn't fit those).

Status: core v1
Built on numpy + scipy — genuinely numerical (finite differences, quadrature,
root-bracketing), not just sympy evaluated at a point. sympy is used only to
parse the expression string and lambdify it into a fast numeric function.
"""
from __future__ import annotations

import statistics
from typing import Any

import numpy as np
import scipy.integrate
import scipy.optimize
import scipy.stats
import sympy
from sympy.parsing.sympy_parser import (
    implicit_multiplication_application,
    standard_transformations,
    parse_expr,
)

_TRANSFORMATIONS = standard_transformations + (implicit_multiplication_application,)


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): keys match INPUT above, shape depends on "operation".
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    operation: str = kwargs["operation"]

    if operation == "integrate":
        return _integrate(kwargs["expression"], kwargs.get("variable", "x"), kwargs["bounds"])
    if operation == "differentiate":
        return _differentiate(kwargs["expression"], kwargs.get("variable", "x"), kwargs["point"])
    if operation == "root":
        return _root(
            kwargs["expression"],
            kwargs.get("variable", "x"),
            kwargs.get("bounds"),
            kwargs.get("point"),
        )
    if operation == "stats":
        return _stats(kwargs["data"])
    if operation == "probability":
        return _probability(kwargs["distribution"], kwargs["params"])

    raise ValueError(f"unknown operation: {operation!r}")


# --- private helpers ---


def _lambdify(expression: str, variable: str):
    var = sympy.Symbol(variable)
    expr = parse_expr(expression, transformations=_TRANSFORMATIONS)
    return expr, sympy.lambdify(var, expr, modules="numpy")


def _integrate(expression: str, variable: str, bounds: list[float]) -> dict:
    expr, f = _lambdify(expression, variable)
    lower, upper = bounds
    value, _abserr = scipy.integrate.quad(f, lower, upper)
    latex = f"\\int_{{{lower}}}^{{{upper}}} {sympy.latex(expr)} \\, d{variable} \\approx {value:.6g}"
    return {"answer": value, "latex": latex}


def _differentiate(expression: str, variable: str, point: float, h: float = 1e-6) -> dict:
    """Central finite-difference numeric derivative: genuinely numerical
    (not sympy.diff evaluated at a point) — that's the whole distinction
    between this engine and math_engine/symbolic."""
    expr, f = _lambdify(expression, variable)
    value = (f(point + h) - f(point - h)) / (2 * h)
    latex = f"\\left.\\frac{{d}}{{d{variable}}}\\left[{sympy.latex(expr)}\\right]\\right|_{{{variable}={point}}} \\approx {value:.6g}"
    return {"answer": value, "latex": latex}


def _root(expression: str, variable: str, bounds: list[float] | None, point: float | None) -> dict:
    expr, f = _lambdify(expression, variable)
    if bounds is not None:
        lower, upper = bounds
        value = scipy.optimize.brentq(f, lower, upper)
        method = f"bracketed between {lower} and {upper} (Brent's method)"
    elif point is not None:
        value = scipy.optimize.newton(f, point)
        method = f"Newton's method from initial guess {point}"
    else:
        raise ValueError("root operation needs either 'bounds' (bracket) or 'point' (initial guess)")
    latex = f"{sympy.latex(expr)} = 0 \\implies {variable} \\approx {value:.6g}"
    return {"answer": value, "latex": latex, "method": method}


def _stats(data: list[float]) -> dict:
    answer = {
        "mean": statistics.mean(data),
        "median": statistics.median(data),
        "variance": statistics.variance(data) if len(data) > 1 else 0.0,
        "stdev": statistics.stdev(data) if len(data) > 1 else 0.0,
        "min": min(data),
        "max": max(data),
        "count": len(data),
    }
    return {
        "answer": answer,
        "latex": f"n={answer['count']},\\ \\bar{{x}}={answer['mean']:.4g},\\ s={answer['stdev']:.4g}",
    }


def _probability(distribution: str, params: dict) -> dict:
    if distribution == "normal":
        mean, std, x = params["mean"], params["std"], params["x"]
        dist = scipy.stats.norm(loc=mean, scale=std)
        answer = {"pdf": float(dist.pdf(x)), "cdf": float(dist.cdf(x))}
        latex = f"X \\sim \\mathcal{{N}}({mean}, {std}^2),\\ P(X \\le {x}) = {answer['cdf']:.4g}"
    elif distribution == "binomial":
        n, p, k = params["n"], params["p"], params["k"]
        dist = scipy.stats.binom(n, p)
        answer = {"pmf": float(dist.pmf(k)), "cdf": float(dist.cdf(k))}
        latex = f"X \\sim \\text{{Binomial}}({n}, {p}),\\ P(X = {k}) = {answer['pmf']:.4g}"
    else:
        raise ValueError(f"unknown distribution: {distribution!r}")
    return {"answer": answer, "latex": latex}


if __name__ == "__main__":
    import asyncio

    def show(label: str, result: dict) -> None:
        enc = __import__("sys").stdout.encoding or "utf-8"
        print(f"--- {label} ---")
        print("answer:", result["answer"])
        print("latex: ", result["latex"].encode(enc, errors="replace").decode(enc))

    async def demo() -> None:
        show("integrate sin(x) 0..pi", await run(
            operation="integrate", expression="sin(x)", bounds=[0, float(np.pi)]))
        show("differentiate x**2 at x=3 (expect ~6)", await run(
            operation="differentiate", expression="x**2", point=3.0))
        show("root of x**2 - 4 bracketed [0,3] (expect 2)", await run(
            operation="root", expression="x**2 - 4", bounds=[0, 3]))
        show("stats", await run(operation="stats", data=[2, 4, 4, 4, 5, 5, 7, 9]))
        show("normal probability", await run(
            operation="probability", distribution="normal", params={"mean": 0, "std": 1, "x": 1.96}))
        show("binomial probability", await run(
            operation="probability", distribution="binomial", params={"n": 10, "p": 0.5, "k": 5}))

    asyncio.run(demo())
