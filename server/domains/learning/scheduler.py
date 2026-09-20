"""
Spaced repetition scheduling — wraps the `fsrs` package (the official
open-spaced-repetition reference implementation; published default
parameters, not tuned per-user since there's no review-history dataset to
optimize against yet) rather than hand-rolling the FSRS algorithm's
formulas. See models.py's Mastery for why its fsrs_* columns mirror
fsrs.Card's fields directly.

Simplification (documented, not a bug): grading in this app is currently
binary (an answer is correct or not — see assessment/grading.py), so
review_after_attempt() only ever uses two of FSRS's four ratings
(Good/Again), not the full Again/Hard/Good/Easy range. Hard/Easy would
need a confidence or response-time signal this app doesn't collect yet.
"""
from __future__ import annotations

import datetime

from fsrs import Card, Rating, Scheduler, State

from .models import Mastery

# Published FSRS-6 default parameters + desired_retention=0.9 (the
# library's own defaults) — no per-user tuning without a review-history
# dataset to optimize against.
_scheduler = Scheduler()


def _card_from_mastery(mastery: Mastery) -> Card:
    return Card(
        state=State(mastery.fsrs_state),
        step=mastery.fsrs_step,
        stability=mastery.fsrs_stability,
        difficulty=mastery.fsrs_difficulty,
        due=mastery.fsrs_due,
        last_review=mastery.fsrs_last_review,
    )


def _apply_card_to_mastery(mastery: Mastery, card: Card) -> None:
    mastery.fsrs_state = card.state.value
    mastery.fsrs_step = card.step
    mastery.fsrs_stability = card.stability
    mastery.fsrs_difficulty = card.difficulty
    mastery.fsrs_due = card.due
    mastery.fsrs_last_review = card.last_review


def review_after_attempt(mastery: Mastery, correct: bool) -> Mastery:
    """Updates `mastery` in place (FSRS state + counters) after a graded
    attempt. Caller is responsible for adding/committing the session."""
    card = _card_from_mastery(mastery)
    rating = Rating.Good if correct else Rating.Again
    new_card, _review_log = _scheduler.review_card(card, rating)
    _apply_card_to_mastery(mastery, new_card)

    now = datetime.datetime.now(datetime.timezone.utc)
    mastery.attempts += 1
    if correct:
        mastery.correct += 1
        mastery.last_correct_at = now
    else:
        mastery.incorrect += 1
        mastery.last_incorrect_at = now
    return mastery


def retrievability(mastery: Mastery) -> float:
    """Current probability of successful recall, per FSRS's forgetting
    curve — computed from stored state, not stored itself (see models.py's
    docstring for why)."""
    return _scheduler.get_card_retrievability(_card_from_mastery(mastery))


def mastery_score(mastery: Mastery) -> float:
    """Composite 0-1 score blending FSRS retrievability (are they likely
    to remember it right now) with raw accuracy (have they generally
    gotten it right) — retrievability alone would call a concept
    "mastered" purely because it was reviewed recently, even if the
    student has mostly gotten it wrong; accuracy alone ignores forgetting
    entirely. 0.0 before any attempt (retrievability is meaningless with
    no review history).

    Accuracy-weighted (0.6/0.4), not the other way around: retrievability
    sits near 1.0 immediately after ANY review — right or wrong, since it
    measures elapsed-time-since-last-review, and elapsed time is ~0 right
    after answering — so a retrievability-heavy blend would score three
    consecutive wrong answers around 0.6 (misleadingly close to
    "reviewed"). Found via testing (server/tests/test_moderator_explain.py),
    not assumed correct on the first attempt: the original 0.6-retrievability/
    0.4-accuracy weighting produced exactly that misleading result."""
    if mastery.attempts == 0:
        return 0.0
    accuracy = mastery.correct / mastery.attempts
    return round(0.4 * retrievability(mastery) + 0.6 * accuracy, 4)


def serialize_mastery(mastery: Mastery) -> dict:
    return {
        "concept_id": mastery.concept_id,
        "mastery": mastery_score(mastery),
        "retrievability": round(retrievability(mastery), 4) if mastery.attempts else None,
        "attempts": mastery.attempts,
        "correct": mastery.correct,
        "incorrect": mastery.incorrect,
        "last_correct_at": mastery.last_correct_at.isoformat() if mastery.last_correct_at else None,
        "last_incorrect_at": mastery.last_incorrect_at.isoformat() if mastery.last_incorrect_at else None,
        "next_review": mastery.fsrs_due.isoformat(),
    }
