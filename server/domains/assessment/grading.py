"""
Grading — one function per question type, deterministic wherever the type
allows it (blueprint Section 18: "AI should not grade everything purely by
intuition"). Only short_answer/essay go through the LLM.

Expected `submitted_answer`/`correct_answer` shapes by type:
  mcq          — a single option string (compared case/whitespace-insensitive)
  true_false   — "true" | "false" (same normalization)
  fill_in_blank — a single word/short phrase, same normalization as mcq
  multi_select — a list of option strings, compared as a set
  numerical    — a number (or numeric string), compared within `tolerance`
  equation     — a sympy-parseable expression string, compared for symbolic
                 equivalence (not string equality — "x+1" and "1+x" both
                 grade correct against "x + 1")
  matching     — a dict of {item: matched_item}, compared as a dict (order
                 doesn't matter, every key must match)
  ordering     — a list in a specific sequence, compared element-by-element
                 (order DOES matter, unlike multi_select)
  short_answer — free text, evaluated by the LLM for semantic correctness
  essay        — longer free text, evaluated by the LLM against
                 correct_answer treated as a model answer / key points list,
                 not graded for exact match (no rubric infrastructure exists
                 yet — this is the same "AI-evaluated, no deterministic
                 fallback" honesty level as short_answer, not the richer
                 rubric+AI blueprint Section 18 describes)

Not yet supported, deliberately (see UnsupportedQuestionType, and
STUDY_OS_PROGRESS.md's 2026-09-14 entry for why each is out of scope for
now rather than silently missing): oral (needs the voice pipeline, which
this session decided stays client-native, not backend, entirely separate
concern), code (needs a sandboxed execution environment — a real security
surface that deserves its own dedicated pass, not folded in here),
diagram_labeling/graph_interpretation (need spatial/visual answer formats
that don't have a defined shape yet).
"""
from __future__ import annotations

from typing import Any

import sympy
from sympy.parsing.sympy_parser import (
    implicit_multiplication_application,
    parse_expr,
    standard_transformations,
)

from ... import engines
from .models import GRADABLE_TYPES, Question

_TRANSFORMATIONS = standard_transformations + (implicit_multiplication_application,)


class UnsupportedQuestionType(Exception):
    def __init__(self, question_type: str):
        super().__init__(
            f"grading for question type {question_type!r} is not yet supported "
            f"(supported: {sorted(GRADABLE_TYPES)})"
        )
        self.question_type = question_type


class GradingInputError(Exception):
    """The submitted answer's shape doesn't match what this question type
    expects (e.g. a string where multi_select needs a list) — a 400, not a
    grading failure."""


class GradingUnavailable(Exception):
    """The LLM call needed for short_answer grading failed — surfaced
    honestly rather than guessing a grade (unlike moderator/engine.py's
    _author_text, there is no safe deterministic fallback for semantic
    correctness)."""


def _normalize(value: Any) -> str:
    return str(value).strip().lower()


async def grade(question: Question, submitted_answer: Any, model_config: dict) -> tuple[bool, str | None, str]:
    """Returns (is_correct, feedback, evaluated_by)."""
    if question.type not in GRADABLE_TYPES:
        raise UnsupportedQuestionType(question.type)

    if question.type in ("mcq", "true_false", "fill_in_blank"):
        return _grade_choice(question, submitted_answer)
    if question.type == "multi_select":
        return _grade_multi_select(question, submitted_answer)
    if question.type == "numerical":
        return _grade_numerical(question, submitted_answer)
    if question.type == "equation":
        return _grade_equation(question, submitted_answer)
    if question.type == "matching":
        return _grade_matching(question, submitted_answer)
    if question.type == "ordering":
        return _grade_ordering(question, submitted_answer)
    if question.type == "essay":
        return await _grade_essay(question, submitted_answer, model_config)
    return await _grade_short_answer(question, submitted_answer, model_config)


def _grade_choice(question: Question, submitted_answer: Any) -> tuple[bool, None, str]:
    return _normalize(submitted_answer) == _normalize(question.correct_answer), None, "deterministic"


def _grade_multi_select(question: Question, submitted_answer: Any) -> tuple[bool, None, str]:
    if not isinstance(submitted_answer, list):
        raise GradingInputError("multi_select answer must be a list of option strings")
    if not isinstance(question.correct_answer, list):
        raise GradingInputError("multi_select question's correct_answer must be a list")
    given = {_normalize(v) for v in submitted_answer}
    correct = {_normalize(v) for v in question.correct_answer}
    return given == correct, None, "deterministic"


def _grade_numerical(question: Question, submitted_answer: Any) -> tuple[bool, None, str]:
    try:
        given = float(submitted_answer)
        correct = float(question.correct_answer)
    except (TypeError, ValueError) as exc:
        raise GradingInputError(f"numerical answer must be a number: {exc}") from exc
    tolerance = question.tolerance if question.tolerance is not None else 1e-9
    return abs(given - correct) <= tolerance, None, "deterministic"


def _grade_equation(question: Question, submitted_answer: Any) -> tuple[bool, None, str]:
    try:
        given_expr = parse_expr(str(submitted_answer), transformations=_TRANSFORMATIONS)
        correct_expr = parse_expr(str(question.correct_answer), transformations=_TRANSFORMATIONS)
        is_correct = sympy.simplify(given_expr - correct_expr) == 0
    except Exception as exc:
        raise GradingInputError(f"could not parse equation: {exc}") from exc
    return bool(is_correct), None, "deterministic"


def _grade_matching(question: Question, submitted_answer: Any) -> tuple[bool, None, str]:
    if not isinstance(submitted_answer, dict):
        raise GradingInputError("matching answer must be a {item: matched_item} object")
    if not isinstance(question.correct_answer, dict):
        raise GradingInputError("matching question's correct_answer must be a {item: matched_item} object")
    given = {_normalize(k): _normalize(v) for k, v in submitted_answer.items()}
    correct = {_normalize(k): _normalize(v) for k, v in question.correct_answer.items()}
    return given == correct, None, "deterministic"


def _grade_ordering(question: Question, submitted_answer: Any) -> tuple[bool, None, str]:
    if not isinstance(submitted_answer, list):
        raise GradingInputError("ordering answer must be a list")
    if not isinstance(question.correct_answer, list):
        raise GradingInputError("ordering question's correct_answer must be a list")
    given = [_normalize(v) for v in submitted_answer]
    correct = [_normalize(v) for v in question.correct_answer]
    # Order matters here (unlike multi_select's set comparison) — that's
    # the entire point of an ordering question.
    return given == correct, None, "deterministic"


_SHORT_ANSWER_PROMPT = """You are grading a student's short-answer response.

Question: {prompt}
Expected answer (for your reference, the student did not see this): {correct}
Student's answer: {submitted}

Judge whether the student's answer is substantively correct — same meaning \
is enough, exact wording is not required. Start your reply with the single \
word "Correct" or "Incorrect", then a brief explanation."""


def _parse_verdict(text: str) -> bool | None:
    """Finds whichever of "correct"/"incorrect" appears FIRST in the
    response and treats that as the verdict — deliberately not requiring a
    strict "VERDICT: correct" prefix. Found via testing against the real
    local ("tiny") model: despite the prompt asking for that exact format,
    it replied "Incorrect\\n<explanation>" — a strict-prefix parser
    rejected a perfectly usable answer as "unparseable". Returns None if
    neither word appears anywhere."""
    lowered = text.lower()
    incorrect_idx = lowered.find("incorrect")

    correct_idx = -1
    search_from = 0
    while True:
        idx = lowered.find("correct", search_from)
        if idx == -1:
            break
        # skip an occurrence that's actually the tail of "incorrect"
        if lowered[max(0, idx - 2):idx] != "in":
            correct_idx = idx
            break
        search_from = idx + 1

    if incorrect_idx == -1 and correct_idx == -1:
        return None
    if incorrect_idx == -1:
        return True
    if correct_idx == -1:
        return False
    return correct_idx < incorrect_idx


async def _grade_via_llm(prompt: str, model_config: dict, *, max_tokens: int) -> tuple[bool, str, str]:
    """Shared by short_answer and essay: call model_router, parse a
    correct/incorrect verdict out of whatever it says (see _parse_verdict),
    surface a clear failure rather than guessing a grade if the call fails
    or comes back unparseable."""
    try:
        result = await engines.model_router.run(prompt=prompt, max_tokens=max_tokens, **model_config)
        text = result["text"].strip()
    except Exception as exc:
        raise GradingUnavailable(f"AI grading unavailable: {exc}") from exc

    if not text:
        raise GradingUnavailable("AI grading returned an empty response")

    is_correct = _parse_verdict(text)
    if is_correct is None:
        raise GradingUnavailable(f"AI grading returned an unparseable response: {text!r}")

    feedback_line = next((line for line in text.splitlines() if line.upper().startswith("FEEDBACK:")), None)
    feedback = feedback_line.split(":", 1)[1].strip() if feedback_line else text[:500]
    return is_correct, feedback, "ai"


async def _grade_short_answer(
    question: Question, submitted_answer: Any, model_config: dict
) -> tuple[bool, str, str]:
    prompt = _SHORT_ANSWER_PROMPT.format(
        prompt=question.prompt, correct=question.correct_answer, submitted=submitted_answer
    )
    return await _grade_via_llm(prompt, model_config, max_tokens=150)


_ESSAY_PROMPT = """You are grading a student's essay response, generously \
but fairly — like a teacher giving credit for genuine understanding, not \
a checklist audit.

Question: {prompt}
Model answer / key points expected (for your reference, the student did not see this): {correct}
Student's essay: {submitted}

Mark this CORRECT if the student identifies MOST of the main ideas and \
shows real understanding of the topic, even if they don't mention every \
single point, use different wording, or add extra detail not in the model \
answer. Only mark it INCORRECT if the essay is largely off-topic, factually \
wrong, or missing nearly all of the expected substance. Start your reply \
with the single word "Correct" or "Incorrect", then a brief explanation of \
what was covered well or missing."""


async def _grade_essay(question: Question, submitted_answer: Any, model_config: dict) -> tuple[bool, str, str]:
    prompt = _ESSAY_PROMPT.format(
        prompt=question.prompt, correct=question.correct_answer, submitted=submitted_answer
    )
    return await _grade_via_llm(prompt, model_config, max_tokens=300)
