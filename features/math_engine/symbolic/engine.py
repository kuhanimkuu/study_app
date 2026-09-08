"""
Symbolic math — arithmetic, algebra, calculus (differentiation, integration),
equations, basic matrix operations. Solves symbolically and returns steps.

INPUT (JSON) — what this engine receives:
{
    "expression": "2*x + 3 = 7",
    "variable": "x",           // optional, default "x"
    "operation": "solve"       // optional: solve | simplify | differentiate | integrate | matrix_det | matrix_inverse
}

If "operation" is omitted, it's inferred: an expression containing "=" is
treated as "solve", otherwise "simplify". Differentiate/integrate/matrix
operations must be requested explicitly — there's no reliable way to guess
"integrate this" from a bare expression string.

OUTPUT (JSON) — what this engine returns:
{
    "answer": "2",
    "latex": "x = 2",
    "steps": [
        "Move all terms to one side: 2*x - 4 = 0",
        "Isolate x: x = 4/2 = 2"
    ]
}

Status: core v1
Built on sympy.

Honesty note on "steps": real step-by-step derivation is only implemented
for linear equations in one variable (the common case). For anything else
(nonlinear equations, differentiation, integration, matrices), "steps"
contains one line stating what sympy computed, not a fabricated
rule-by-rule derivation — matching this project's pattern of saying
"not implemented" rather than faking pedagogy (see pdf_processing's
"equations": [] for the same idea).
"""
from __future__ import annotations

from typing import Any

import sympy
from sympy.parsing.sympy_parser import (
    implicit_multiplication_application,
    standard_transformations,
    parse_expr,
)

_TRANSFORMATIONS = standard_transformations + (implicit_multiplication_application,)


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): {"expression": "...", "variable"?: str, "operation"?: str}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    expression: str = kwargs["expression"]
    variable: str = kwargs.get("variable", "x")
    operation: str = kwargs.get("operation") or _infer_operation(expression)
    var = sympy.Symbol(variable)

    if operation == "solve":
        return _solve(expression, var)
    if operation == "simplify":
        return _simplify(expression)
    if operation == "differentiate":
        return _differentiate(expression, var)
    if operation == "integrate":
        return _integrate(expression, var)
    if operation == "matrix_det":
        return _matrix_det(expression)
    if operation == "matrix_inverse":
        return _matrix_inverse(expression)

    raise ValueError(f"unknown operation: {operation!r}")


# --- private helpers ---


def _infer_operation(expression: str) -> str:
    return "solve" if "=" in expression else "simplify"


def _parse(text: str) -> sympy.Expr:
    return parse_expr(text, transformations=_TRANSFORMATIONS)


def _parse_equation(expression: str) -> sympy.Eq:
    if "=" in expression:
        lhs_str, rhs_str = expression.split("=", 1)
        return sympy.Eq(_parse(lhs_str), _parse(rhs_str))
    return sympy.Eq(_parse(expression), 0)


def _solve(expression: str, var: sympy.Symbol) -> dict:
    eq = _parse_equation(expression)
    solutions = sympy.solve(eq, var)

    steps = _linear_solve_steps(eq, var) or [
        f"Solved {sympy.latex(eq)} for {var} using sympy.solve "
        "(no step-by-step derivation implemented for this equation's form)."
    ]

    if not solutions:
        answer, latex = "no solution", "\\text{no solution}"
    elif len(solutions) == 1:
        answer, latex = str(solutions[0]), f"{var} = {sympy.latex(solutions[0])}"
    else:
        answer = ", ".join(str(s) for s in solutions)
        latex = sympy.latex(solutions)

    return {"answer": answer, "latex": latex, "steps": steps}


def _linear_solve_steps(eq: sympy.Eq, var: sympy.Symbol) -> list[str] | None:
    """Real step-by-step derivation, only for a*var + b = 0 (degree 1)."""
    diff = sympy.expand(eq.lhs - eq.rhs)
    poly = diff.as_poly(var)
    if poly is None or poly.degree() != 1:
        return None

    a = poly.coeff_monomial(var)
    b = poly.coeff_monomial(1)
    solution = sympy.nsimplify(-b / a)

    steps = [f"Move all terms to one side: {sympy.latex(a * var + b)} = 0"]
    if b > 0:
        steps.append(f"Subtract {sympy.latex(b)} from both sides: {sympy.latex(a * var)} = {sympy.latex(-b)}")
    elif b < 0:
        steps.append(f"Add {sympy.latex(-b)} to both sides: {sympy.latex(a * var)} = {sympy.latex(-b)}")
    if a != 1:
        steps.append(f"Divide both sides by {sympy.latex(a)}: {var} = {sympy.latex(solution)}")
    else:
        steps.append(f"{var} = {sympy.latex(solution)}")
    return steps


def _simplify(expression: str) -> dict:
    expr = _parse(expression)
    simplified = sympy.simplify(expr)
    return {
        "answer": str(simplified),
        "latex": sympy.latex(simplified),
        "steps": [f"Simplified {sympy.latex(expr)} to {sympy.latex(simplified)} using sympy.simplify."],
    }


def _differentiate(expression: str, var: sympy.Symbol) -> dict:
    expr = _parse(expression)
    derivative = sympy.simplify(sympy.diff(expr, var))
    return {
        "answer": str(derivative),
        "latex": sympy.latex(derivative),
        "steps": [
            f"d/d{var} [{sympy.latex(expr)}] = {sympy.latex(derivative)} "
            "(computed via sympy.diff; rule-by-rule derivation not implemented)."
        ],
    }


def _integrate(expression: str, var: sympy.Symbol) -> dict:
    expr = _parse(expression)
    integral = sympy.integrate(expr, var)
    latex = sympy.latex(integral) + " + C"
    return {
        "answer": f"{integral} + C",
        "latex": latex,
        "steps": [
            f"Integral of {sympy.latex(expr)} d{var} = {latex} "
            "(computed via sympy.integrate; rule-by-rule derivation not implemented; "
            "+C is the constant of integration, added manually since sympy omits it)."
        ],
    }


def _parse_matrix(expression: str) -> sympy.Matrix:
    return sympy.sympify(expression, locals={"Matrix": sympy.Matrix})


def _matrix_det(expression: str) -> dict:
    matrix = _parse_matrix(expression)
    det = matrix.det()
    return {
        "answer": str(det),
        "latex": sympy.latex(det),
        "steps": [f"det({sympy.latex(matrix)}) = {sympy.latex(det)} (computed via sympy Matrix.det())."],
    }


def _matrix_inverse(expression: str) -> dict:
    matrix = _parse_matrix(expression)
    inverse = matrix.inv()
    return {
        "answer": str(inverse),
        "latex": sympy.latex(inverse),
        "steps": [f"{sympy.latex(matrix)}^{{-1}} = {sympy.latex(inverse)} (computed via sympy Matrix.inv())."],
    }


if __name__ == "__main__":
    import asyncio

    def show(label: str, result: dict) -> None:
        enc = __import__("sys").stdout.encoding or "utf-8"
        print(f"--- {label} ---")
        print("answer:", result["answer"])
        print("latex: ", result["latex"].encode(enc, errors="replace").decode(enc))
        for step in result["steps"]:
            print("step:  ", step.encode(enc, errors="replace").decode(enc))

    async def demo() -> None:
        show("solve linear", await run(expression="2*x + 3 = 7"))
        show("solve quadratic", await run(expression="x**2 - 5*x + 6 = 0"))
        show("simplify", await run(expression="(x**2 - 1)/(x - 1)"))
        show("differentiate", await run(expression="x**3 + 3*x**2", operation="differentiate"))
        show("integrate", await run(expression="2*x", operation="integrate"))
        show("matrix det", await run(expression="Matrix([[1,2],[3,4]])", operation="matrix_det"))
        show("matrix inverse", await run(expression="Matrix([[1,2],[3,4]])", operation="matrix_inverse"))

    asyncio.run(demo())
