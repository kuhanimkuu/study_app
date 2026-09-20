/// Consecutive-day study streak, computed client-side from real activity
/// (study sessions + practice attempts, each already carrying a real
/// server timestamp) — never a fabricated/hardcoded number. Shared by
/// `ProgressScreen`'s insights section and `HomeScreen`'s streak badge so
/// both surfaces can never disagree on the same real data.
///
/// [activity] items must each have a `_timestamp` ISO-8601 string key —
/// see `ProgressScreen`'s merged-activity-feed construction.
int computeStudyStreak(List<Map<String, dynamic>> activity) {
  DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  final activeDays = activity.map((a) => dateOnly(DateTime.parse(a['_timestamp'] as String).toLocal())).toSet();

  var streak = 0;
  var day = dateOnly(DateTime.now());
  while (activeDays.contains(day)) {
    streak++;
    day = day.subtract(const Duration(days: 1));
  }
  return streak;
}
