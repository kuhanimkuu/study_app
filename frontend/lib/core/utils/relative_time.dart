/// "just now", "5 min ago", "2 h ago", "yesterday", "3 days ago",
/// "12 Oct" — for an ISO timestamp from the API. Unparseable input comes
/// back as it was, so a bad value never hides the row it's in.
String relativeTime(String? iso, {DateTime? now}) {
  if (iso == null) return '';
  final time = DateTime.tryParse(iso)?.toLocal();
  if (time == null) return iso;
  final current = now ?? DateTime.now();
  final diff = current.difference(time);
  if (diff.isNegative || diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  final days = DateTime(current.year, current.month, current.day)
      .difference(DateTime(time.year, time.month, time.day))
      .inDays;
  if (days == 1) return 'yesterday';
  if (days < 7) return '$days days ago';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final label = '${time.day} ${months[time.month - 1]}';
  return time.year == current.year ? label : '$label ${time.year}';
}

/// When a flashcard is next due, from its ISO `due`: "Due now", "Due in
/// 3 h", "Due tomorrow", "Due in 5 days".
String dueLabel(String? iso, {DateTime? now}) {
  final due = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  if (due == null) return '';
  final current = now ?? DateTime.now();
  final diff = due.difference(current);
  if (diff.inMinutes < 1) return 'Due now';
  if (diff.inHours < 1) return 'Due in ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'Due in ${diff.inHours} h';
  final days = DateTime(due.year, due.month, due.day)
      .difference(DateTime(current.year, current.month, current.day))
      .inDays;
  if (days <= 1) return 'Due tomorrow';
  return 'Due in $days days';
}
