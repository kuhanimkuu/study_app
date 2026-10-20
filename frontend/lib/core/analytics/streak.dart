/// Consecutive-day study streak, computed client-side from real activity
/// (study sessions + practice attempts, each already carrying a real
/// server timestamp) — never a fabricated/hardcoded number. Shared by
/// `ProgressScreen`'s insights section and `HomeScreen`'s streak badge so
/// both surfaces can never disagree on the same real data.
///
/// [activity] items must each have a `_timestamp` ISO-8601 string key —
/// see `ProgressScreen`'s merged-activity-feed construction.
///
/// [endingYesterday] counts the run up to yesterday instead — the streak
/// that's still alive but at risk on a day with no study yet (today's
/// count is 0 until the student does something). Study reminders use it.
int computeStudyStreak(List<Map<String, dynamic>> activity, {bool endingYesterday = false}) {
  DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  final activeDays = activity.map((a) => dateOnly(DateTime.parse(a['_timestamp'] as String).toLocal())).toSet();

  var streak = 0;
  final today = dateOnly(DateTime.now());
  var day = endingYesterday ? DateTime(today.year, today.month, today.day - 1) : today;
  while (activeDays.contains(day)) {
    streak++;
    day = day.subtract(const Duration(days: 1));
  }
  return streak;
}
