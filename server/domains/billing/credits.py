"""
App credits for the hosted tier (2026-10-27, plan Step 4). Students see
credits, never provider cost, markup or tokens: each feature costs a fixed
number of credits, whatever model and however many tokens it took.

1 credit sells for $0.01 (a 100-credit pack is $1), so wallet_balances.
balance_cents and a ledger row's amount_cents now hold credits, one for
one, and old balances carry over unchanged.

Prices are set from the worst case, not the average: every feature's
output is capped (server/ai/moderator/style.py and each call site's
max_tokens), so its largest possible bill on deepseek-chat ($0.27 in /
$1.10 out per million tokens) is known. Each price stays above that. See
docs/COST_AND_CREDITS.md for the sums, and server/scripts/cost_report.py
for what features really cost once students use them.

Behind the credits sits a hidden monthly allowance (service.
enforce_hosted_allowance): a cap on what one student's hosted calls may
cost Study OS in a month, whatever the provider. It is what keeps the
worst case below the price if the hosted model is ever changed to a dearer
one before these prices are.
"""
from __future__ import annotations

# source (what record_ai_usage is called with) -> credits per call.
# Worst-case cost on deepseek-chat in the comment; price is $0.01/credit.
FEATURE_CREDITS: dict[str, int] = {
    "chat": 1,         # reply 1,400 out + marking 1,200 out, ~6k in: $0.0045
    "chat_exam": 2,    # exam-level reply 2,240 out + marking: $0.0054
    "pdf_summary": 2,  # study guide or practice exam, 1,800 out: $0.0025
    "lesson": 3,       # 5,000 out, ~3k in: $0.0063
    "go_deeper": 1,    # picks 700 out, ~5k in of candidates: $0.0021
    "explain": 1,      # concept explanation, up to 1,500 out: $0.0025
    "generation": 2,   # practice questions, flashcards, concepts, up to 2,350 out: $0.0042
    "grading": 1,      # 300 out: $0.0011
    "check": 0,        # the "test my AI" button
}

# Anything not listed costs this, so a new feature is never free by accident.
DEFAULT_CREDITS = 2

CREDIT_PRICE_CENTS = 1

# What a student can buy. No real payment yet (payment_provider.py).
PACKS: dict[str, dict] = {
    "small": {"credits": 100, "price_cents": 100, "label": "100 credits"},
    "medium": {"credits": 550, "price_cents": 500, "label": "550 credits"},
    "large": {"credits": 1200, "price_cents": 1000, "label": "1,200 credits"},
}

# How features are named to students.
FEATURE_NAMES: dict[str, str] = {
    "chat": "Chat answer",
    "chat_exam": "Exam-level answer",
    "pdf_summary": "Study guide",
    "lesson": "Lesson",
    "go_deeper": "Go deeper",
    "explain": "Explanation",
    "generation": "Practice or flashcards",
    "grading": "Marking",
    "check": "AI test",
}


def credits_for(source: str) -> int:
    return FEATURE_CREDITS.get(source, DEFAULT_CREDITS)


def price_list() -> list[dict]:
    return [
        {"feature": source, "name": FEATURE_NAMES.get(source, source), "credits": credits}
        for source, credits in FEATURE_CREDITS.items()
        if credits > 0
    ]
