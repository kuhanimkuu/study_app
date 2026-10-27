"""
Teacher-quality check with a real model (Study OS plan, step 1).

Runs the same student questions, three scripted conversations and one
lesson through the real chat/lesson code with DeepSeek, and writes the
transcripts plus token use and cost to eval_runs/<label>-<time>.md, so
answers before and after a change can be compared side by side.

    python -m server.scripts.teacher_eval before
    python -m server.scripts.teacher_eval after

Needs DEEPSEEK_API_KEY in .env (never printed). About 20 model calls; the
cost is in the report's summary.
"""
from __future__ import annotations

import asyncio
import datetime
import os
import sys
import time
from pathlib import Path

from dotenv import load_dotenv

from features.moderator import engine as moderator
from server import engines
from server.ai.moderator.style import DEPTH_MAX_TOKENS, LESSON_MAX_TOKENS
from server.domains.billing import pricing
from server.domains.tutor.lessons import lesson_prompt, parse_lesson

ROOT = Path(__file__).resolve().parents[2]
MODEL = "deepseek-chat"

QUESTIONS = [
    ("maths", "Solve x^2 - 5x + 6 = 0"),
    ("maths", "Explain integration by parts"),
    ("physics", "Why does ice float on water?"),
    ("physics", "Explain Newton's second law"),
    ("chemistry", "What is an exothermic reaction?"),
    ("biology", "Explain osmosis"),
    ("programming", "What is recursion in Python?"),
    ("programming", "What is the time complexity of binary search and why?"),
    ("essays", "How do I structure an argumentative essay?"),
    ("essays", "What makes a strong thesis statement?"),
]

# (name, what Sage had just taught, its check question, the student's replies in turn).
# Fixed, so every run marks the same answers to the same question.
CONVERSATIONS = [
    ("right", "The power rule: to differentiate x^n, bring n down and lower the power by one.",
     "What is the derivative of x^3?", ["3x^2"]),
    ("wrong twice", "The power rule: to differentiate x^n, bring n down and lower the power by one.",
     "What is the derivative of x^3?", ["x^2", "x^4/4?"]),
    ("correct but slow", "A percentage is a number out of 100.",
     "What is 25% of 80?", ["I divided 80 by 100 to get 0.8, then multiplied 0.8 by 25 and got 20"]),
    ("gave up", "Ice is less dense than liquid water because of how its molecules are arranged.",
     "Why is ice less dense than liquid water?", ["I don't know, can you show me?"]),
]

LESSON_TOPIC = "Photosynthesis"


class Meter:
    def __init__(self):
        self.calls, self.input_tokens, self.output_tokens = 0, 0, 0

    def add(self, usage: dict | None):
        if usage:
            self.calls += 1
            self.input_tokens += usage.get("input_tokens") or 0
            self.output_tokens += usage.get("output_tokens") or 0

    def cost_usd(self) -> float | None:
        micro = pricing.estimate_cost_micro_usd("deepseek", MODEL, self.input_tokens, self.output_tokens)
        return None if micro is None else micro / 1_000_000


def _text(result: dict) -> str:
    parts = []
    for block in result.get("blocks", []):
        kind = block.get("type")
        if kind in ("text", "source"):
            parts.append(block.get("content", ""))
        elif kind == "clarification":
            parts.append(f"[asks] {block.get('question')}")
        elif kind == "links":
            parts.append("[links] " + ", ".join(link["label"] for link in block.get("links", [])))
        elif kind == "model_unavailable":
            parts.append(f"[model unavailable] {block.get('message')}")
        elif kind == "error":
            parts.append(f"[error] {block.get('message')}")
        else:
            parts.append(f"[{kind} block]")
    return "\n\n".join(parts)


async def ask(config: dict, meter: Meter, content: str, history: list[dict] | None = None, session: str = "eval") -> dict:
    # As the server sends it for a default student: tutor mode on, full
    # depth, and its length cap (server/ai/moderator/style.py).
    result = await moderator.run(
        input_type="text", content=content, session_id=session, user_id=None, model_config=dict(config),
        history=history or [], tutor_mode=True, depth="full", personality_max_tokens=DEPTH_MAX_TOKENS["full"],
    )
    meter.add(result.get("_usage"))
    return result


async def main(label: str) -> None:
    load_dotenv(ROOT / ".env")
    key = os.environ.get("DEEPSEEK_API_KEY", "").strip()
    if not key:
        sys.exit("DEEPSEEK_API_KEY isn't set in .env")
    config = {"backend": "deepseek", "tier": "tiny", "api_key": key, "model_name": MODEL}
    meter = Meter()
    out: list[str] = [f"# Teacher eval — {label} — {datetime.datetime.now():%Y-%m-%d %H:%M}", f"Model: {MODEL}", ""]

    out.append("## Questions\n")
    for i, (subject, question) in enumerate(QUESTIONS, start=1):
        started = time.perf_counter()
        result = await ask(config, meter, question, session=f"eval-q{i}")
        took = time.perf_counter() - started
        answer = _text(result)
        out += [f"### {i}. [{subject}] {question}", f"_{took:.1f}s, {len(answer.split())} words, engine {result.get('activity', {}).get('engine')}_", "", answer, ""]
        print(f"question {i}/{len(QUESTIONS)} done ({took:.1f}s)")

    out.append("## Conversations\n")
    for name, taught, check, replies in CONVERSATIONS:
        session = f"eval-conv-{name}"
        sage = f"{taught}\n**Check:** {check}"
        history = [{"role": "user", "text": "Can you teach me this?"}, {"role": "assistant", "text": sage}]
        out += [f"### Conversation: {name}", f"**Sage:** {sage}", ""]
        for reply in replies:
            result = await ask(config, meter, reply, history=history, session=session)
            answer = _text(result)
            activity = result.get("activity", {})
            out += [f"**Student:** {reply}", "", f"**Sage:** {answer}", "",
                    f"_verdict: {activity.get('check')} (by {activity.get('check_verified_by')}), "
                    f"misconception: {activity.get('misconception')}_", ""]
            history += [{"role": "user", "text": reply}, {"role": "assistant", "text": answer}]
        print(f"conversation '{name}' done")

    out.append(f"## Lesson: {LESSON_TOPIC}\n")
    started = time.perf_counter()
    raw = await engines.model_router.run(
        prompt=lesson_prompt(LESSON_TOPIC, None, None, ""), max_tokens=LESSON_MAX_TOKENS, **config
    )
    meter.add(raw.get("usage"))
    took = time.perf_counter() - started
    try:
        lesson = parse_lesson(raw.get("text") or "", LESSON_TOPIC)
        out.append(f"_{took:.1f}s — parsed OK: {len(lesson['steps'])} steps, "
                   f"{sum(1 for s in lesson['steps'] if s['check'])} checks, {len(lesson['recap'])} recap cards_\n")
        for n, step in enumerate(lesson["steps"], start=1):
            out += [f"### Step {n}: {step['heading']}", f"_{len(step['explanation'].split())} words_", "", step["explanation"], ""]
            if step["check"]:
                check = step["check"]
                out += [f"**Check ({check['type']}):** {check['prompt']}", f"Options: {check['options']}" if check["options"] else "",
                        f"Answer: {check['correct_answer']} — {check['why']}", ""]
        if lesson["worked_example"]:
            out += ["### Worked example", lesson["worked_example"]["problem"], "", lesson["worked_example"]["solution"], ""]
    except Exception as exc:
        out += [f"_{took:.1f}s — FAILED TO PARSE: {getattr(exc, 'detail', exc)}_", "", "```", (raw.get("text") or "")[:3000], "```", ""]
    print("lesson done")

    cost = meter.cost_usd()
    summary = [
        "## Summary", f"- model calls with usage: {meter.calls}",
        f"- input tokens: {meter.input_tokens}, output tokens: {meter.output_tokens}",
        f"- estimated cost: {'unknown (no price for model)' if cost is None else f'${cost:.4f}'}", "",
    ]
    out[3:3] = summary
    folder = ROOT / "eval_runs"
    folder.mkdir(exist_ok=True)
    path = folder / f"{label}-{datetime.datetime.now():%Y%m%d-%H%M}.md"
    path.write_text("\n".join(out), encoding="utf-8")
    print("\n".join(summary))
    print(f"report: {path}")


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1] if len(sys.argv) > 1 else "run"))
