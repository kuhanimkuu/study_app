"""The teacher loop (2026-10-27, Study OS plan step 1): depth-shaped
teaching, and replies to Sage's check question marked with structured JSON —
maths verified by SymPy, a hint before the solution, the better method for a
correct-but-slow answer, misconceptions recorded. The model is faked."""
from __future__ import annotations

import json
import uuid

import pytest
from sqlalchemy import delete

from features.moderator import engine as moderator
from server import engines
from server.db.session import async_session
from server.domains.identity.models import User

CHECK = {"question": "What is the derivative of x^5?", "second_try": False, "teaching": "Power rule: n·x^(n-1)."}


def _marking(**overrides) -> dict:
    base = {
        "is_answer": True, "gave_up": False, "verdict": "wrong", "what_was_right": None,
        "error_step": "You lowered the power but didn't bring the 5 down.",
        "misconception": "Forgetting to multiply by the old exponent.", "misconception_type": "Forgot Power Rule Coefficient",
        "hint": "What do you multiply by before lowering the power?", "full_solution": "5x^4: bring 5 down, 5-1=4.",
        "better_method": None, "expected_answer": "5x^4", "student_answer": "x^4", "follow_up": "Differentiate x^7.",
    }
    return {**base, **overrides}


# --- the marking parser -------------------------------------------------------

def test_parse_marking_reads_fenced_json_and_tidies_the_label():
    parsed = moderator.parse_marking("Sure:\n```json\n" + json.dumps(_marking()) + "\n```")
    assert parsed["verdict"] == "wrong"
    assert parsed["misconception_type"] == "forgot_power_rule_coefficient"
    assert parsed["better_method"] is None


@pytest.mark.parametrize("text", ["not json", json.dumps({"verdict": "wrong"}), json.dumps(_marking(verdict="meh"))])
def test_parse_marking_refuses_unusable_replies(text):
    assert moderator.parse_marking(text) is None


def test_a_new_question_is_not_an_answer():
    parsed = moderator.parse_marking(json.dumps({"is_answer": False}))
    assert parsed["is_answer"] is False


# --- SymPy decides maths ---------------------------------------------------------

@pytest.mark.parametrize(
    "expected, given, same",
    [("5x^4", "5*x**4", True), ("3x²", "3 x^2", True), ("x = 2", "2", True), ("1/2", "0.5", True),
     ("5x^4", "x^4", False), ("20", "20.0", True)],
)
def test_same_math(expected, given, same):
    assert moderator.same_math(expected, given) is same


@pytest.mark.parametrize("given", ["__import__('os')", "x.real", "eval(1)", "open", "photosynthesis", None, ""])
def test_same_math_only_reads_plain_maths(given):
    assert moderator.same_math("5", given) is None


# --- how the tutor answers ---------------------------------------------------------

def test_wrong_first_try_gets_a_hint_not_the_answer():
    text = moderator.marking_reply(_marking(), CHECK)
    assert "Not quite" in text and "**Hint:**" in text and "**Try again:** What is the derivative" in text
    assert "5x^4" not in text  # the solution waits


def test_wrong_second_try_gets_the_full_solution():
    text = moderator.marking_reply(_marking(), {**CHECK, "second_try": True})
    assert "**Solution:**" in text and "5x^4" in text and "**Check:** Differentiate x^7." in text


def test_giving_up_gets_the_solution_kindly():
    text = moderator.marking_reply(_marking(gave_up=True), CHECK)
    assert text.startswith("No problem") and "**Solution:**" in text


def test_partly_right_points_at_the_step():
    text = moderator.marking_reply(_marking(verdict="partial", what_was_right="You lowered the power correctly."), CHECK)
    assert "Almost" in text and "**Where it went wrong:**" in text and "**Try again:**" in text


def test_correct_but_slow_gets_the_better_method():
    text = moderator.marking_reply(
        _marking(verdict="correct", what_was_right="Right answer.", better_method="25% is a quarter: 80 ÷ 4 = 20."), CHECK
    )
    assert "Correct" in text and "**A quicker way:** 25% is a quarter" in text and "**Check:**" in text


def test_the_open_check_is_found_only_right_after_sage_asked():
    history = [{"role": "user", "text": "derivatives?"}, {"role": "assistant", "text": "Use the power rule.\n**Check:** What is d/dx x^5?"}]
    assert moderator._open_check(history)["question"] == "What is d/dx x^5?"
    assert moderator._open_check(history + [{"role": "user", "text": "5x^4"}]) is None
    retry = [{"role": "assistant", "text": "❌ Not quite.\n\n**Hint:** …\n\n**Try again:** What is d/dx x^5?"}]
    assert moderator._open_check(retry)["second_try"] is True


def test_depth_shapes_the_teaching():
    full = moderator._conversation_context([], tutor_mode=True, depth="full")
    assert "**Worked example**" in full and "**Common mistakes**" in full and "**Check:**" in full
    assert "**In the exam**" in moderator._conversation_context([], tutor_mode=True, depth="exam")
    assert "one short paragraph" in moderator._conversation_context([], tutor_mode=True, depth="quick")


# --- end to end through /api/ask/text ------------------------------------------------

@pytest.fixture
async def student(client):
    email = f"pytest_teach_{uuid.uuid4().hex[:10]}@example.com"
    resp = await client.post("/api/auth/signup", json={"email": email, "password": "testpass123"})
    yield {"Authorization": f"Bearer {resp.json()['token']}"}
    async with async_session() as db:
        await db.execute(delete(User).where(User.email == email))
        await db.commit()


HISTORY = [
    {"role": "user", "text": "how do derivatives of powers work?"},
    {"role": "assistant", "text": "Bring the power down, lower it by one.\n**Check:** What is the derivative of x^5?"},
]


async def test_sympy_overrules_the_model_and_the_mistake_is_recorded(client, student, monkeypatch):
    prompts = []

    async def fake(**kwargs):
        prompts.append(kwargs)
        # The model wrongly calls a right answer wrong; SymPy says 5*x**4 == 5x^4.
        return {"text": json.dumps(_marking(student_answer="5*x**4")), "usage": {"input_tokens": 100, "output_tokens": 50}}

    monkeypatch.setattr(engines.model_router, "run", fake)
    resp = await client.post("/api/ask/text", json={"content": "5*x**4", "history": HISTORY}, headers=student)
    body = resp.json()
    assert body["activity"]["check"] == "correct" and body["activity"]["check_verified_by"] == "sympy"
    assert body["blocks"][0]["content"].startswith("✅ **Correct!**")
    assert len(prompts) == 1  # marked once; no second answer written
    assert "<student_answer>\n5*x**4\n</student_answer>" in prompts[0]["prompt"]


async def test_a_wrong_answer_is_a_struggle_with_its_misconception(client, student, monkeypatch):
    async def fake(**kwargs):
        return {"text": json.dumps(_marking()), "usage": None}

    monkeypatch.setattr(engines.model_router, "run", fake)
    body = (await client.post("/api/ask/text", json={"content": "x^4", "history": HISTORY}, headers=student)).json()
    assert body["activity"]["check"] == "wrong"
    assert "struggle" in body["activity"]["labels"]
    assert "misconception:forgot_power_rule_coefficient" in body["activity"]["labels"]
    assert "**Try again:**" in body["blocks"][0]["content"]


async def test_a_new_question_after_a_check_is_answered_normally(client, student, monkeypatch):
    calls = []

    async def fake(**kwargs):
        calls.append(kwargs["prompt"])
        if "marking a student's reply" in kwargs["prompt"]:
            return {"text": json.dumps({"is_answer": False}), "usage": None}
        return {"text": "Integration is the reverse of differentiation.", "usage": None}

    monkeypatch.setattr(engines.model_router, "run", fake)
    body = (await client.post(
        "/api/ask/text", json={"content": "actually, what is integration?", "history": HISTORY}, headers=student
    )).json()
    assert body["blocks"][0]["content"] == "Integration is the reverse of differentiation."
    assert len(calls) == 2 and "check" not in body["activity"]


async def test_both_calls_are_metered(client, student, monkeypatch):
    async def fake(**kwargs):
        if "marking a student's reply" in kwargs["prompt"]:
            return {"text": json.dumps({"is_answer": False}), "usage": {"input_tokens": 10, "output_tokens": 5}}
        return {"text": "An answer.", "usage": {"input_tokens": 20, "output_tokens": 30}}

    monkeypatch.setattr(engines.model_router, "run", fake)
    await client.post("/api/ask/text", json={"content": "new question?", "history": HISTORY}, headers=student)
    meter = (await client.get("/api/v1/billing/ai-usage", headers=student)).json()
    assert meter["all_time"]["input_tokens"] == 30 and meter["all_time"]["output_tokens"] == 35


async def test_depth_sets_the_length_cap(client, student, monkeypatch):
    caps = []

    async def fake(**kwargs):
        caps.append(kwargs["max_tokens"])
        return {"text": "ok", "usage": None}

    monkeypatch.setattr(engines.model_router, "run", fake)
    for depth in ("quick", "full", "exam"):
        await client.post("/api/ask/text", json={"content": "explain entropy", "depth": depth}, headers=student)
    assert caps[0] < caps[1] < caps[2]


async def test_giving_up_is_not_recorded_as_a_misconception(client, student, monkeypatch):
    async def fake(**kwargs):
        return {"text": json.dumps(_marking(gave_up=True, misconception_type="no_attempt")), "usage": None}

    monkeypatch.setattr(engines.model_router, "run", fake)
    body = (await client.post("/api/ask/text", json={"content": "I don't know", "history": HISTORY}, headers=student)).json()
    assert "struggle" in body["activity"]["labels"]
    assert "misconception" not in body["activity"]


def test_marking_is_written_to_the_student():
    assert 'as \"you\"' in moderator._marking_prompt(CHECK, "x^4")
