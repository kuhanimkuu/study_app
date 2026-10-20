// Study reminders (2026-10-20): the week's schedule skips today once the
// student has studied or the time has passed, and only the first reminder
// quotes the real streak and cards due.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:study_os_frontend/core/analytics/streak.dart';
import 'package:study_os_frontend/core/notifications/study_reminders.dart';

void main() {
  const seven = TimeOfDay(hour: 19, minute: 0);

  test('today is included when the time is ahead and nothing studied yet', () {
    final slots = planReminders(now: DateTime(2026, 10, 20, 9), time: seven, dueCards: 3, streak: 4, studiedToday: false);
    expect(slots, hasLength(7));
    expect(slots.first.at, DateTime(2026, 10, 20, 19));
    expect(slots.first.title, 'Your 4-day streak ends tonight');
    expect(slots.first.body, '3 flashcards are due — a quick review keeps it going.');
    expect(slots[1].at, DateTime(2026, 10, 21, 19));
    expect(slots[1].title, 'Time for a quick study session');
    expect(slots.last.at, DateTime(2026, 10, 26, 19));
  });

  test('today is skipped once studied, and after the time has passed', () {
    final studied = planReminders(now: DateTime(2026, 10, 20, 9), time: seven, dueCards: 1, streak: 5, studiedToday: true);
    expect(studied.first.at, DateTime(2026, 10, 21, 19));
    expect(studied.first.title, 'Keep your 5-day streak going');
    expect(studied.first.body, '1 flashcard is due for review.');

    final late = planReminders(now: DateTime(2026, 10, 20, 20), time: seven, dueCards: 0, streak: 0, studiedToday: false);
    expect(late.first.at, DateTime(2026, 10, 21, 19));
    expect(late.first.body, 'Sage has questions ready for you.');
    expect(late, hasLength(7));
  });

  test('month ends roll over correctly', () {
    final slots = planReminders(now: DateTime(2026, 10, 31, 22), time: seven, dueCards: 0, streak: 0, studiedToday: false);
    expect(slots.first.at, DateTime(2026, 11, 1, 19));
  });

  test('the at-risk streak counts up to yesterday', () {
    final now = DateTime.now();
    String daysAgo(int n) => DateTime(now.year, now.month, now.day - n, 12).toUtc().toIso8601String();
    final activity = [for (final n in [1, 2, 3]) {'_timestamp': daysAgo(n)}];
    expect(computeStudyStreak(activity), 0);
    expect(computeStudyStreak(activity, endingYesterday: true), 3);
  });
}
