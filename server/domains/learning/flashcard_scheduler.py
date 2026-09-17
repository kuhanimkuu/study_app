"""Spaced-repetition scheduling for Flashcard — same `fsrs` package as
scheduler.py's Mastery, but using the library's full 4-value Rating scale
(Again/Hard/Good/Easy) rather than the 2-value Good/Again mapping Mastery
uses. Flashcards are self-graded (the student judges their own recall),
which is exactly the case FSRS's full scale is for — unlike a graded
quiz question, there's no separate correctness signal to collapse it
down to binary.
"""
from __future__ import annotations

from fsrs import Card, Rating, Scheduler, State

from .models import Flashcard

_scheduler = Scheduler()

RATINGS = {"again": Rating.Again, "hard": Rating.Hard, "good": Rating.Good, "easy": Rating.Easy}


def _card_from_flashcard(flashcard: Flashcard) -> Card:
    return Card(
        state=State(flashcard.fsrs_state),
        step=flashcard.fsrs_step,
        stability=flashcard.fsrs_stability,
        difficulty=flashcard.fsrs_difficulty,
        due=flashcard.fsrs_due,
        last_review=flashcard.fsrs_last_review,
    )


def _apply_card_to_flashcard(flashcard: Flashcard, card: Card) -> None:
    flashcard.fsrs_state = card.state.value
    flashcard.fsrs_step = card.step
    flashcard.fsrs_stability = card.stability
    flashcard.fsrs_difficulty = card.difficulty
    flashcard.fsrs_due = card.due
    flashcard.fsrs_last_review = card.last_review


def review_flashcard(flashcard: Flashcard, rating: str) -> Flashcard:
    """Updates `flashcard` in place after a self-graded review. Caller is
    responsible for adding/committing the session. `rating` must be one of
    RATINGS' keys — validated by the caller (the router), since a 400 there
    carries more context than one raised from inside this helper."""
    card = _card_from_flashcard(flashcard)
    new_card, _review_log = _scheduler.review_card(card, RATINGS[rating])
    _apply_card_to_flashcard(flashcard, new_card)
    flashcard.reviews += 1
    return flashcard
