import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Daily study reminders (2026-10-20): opt-in from Profile, off by default.
/// Local notifications only — nothing goes through the server, and nothing
/// is sent when the student has turned them off.
///
/// Instead of one repeating notification with fixed text, Home calls
/// [StudyReminders.refresh] each time it loads with the real streak and
/// cards due, which reschedules the next week of reminders: the next one
/// names the streak and the cards waiting, and today's is skipped if the
/// student already studied. If the app isn't opened for days, the rest of
/// the week still fires with general text, then they stop — a forgotten
/// app doesn't nag forever.
class StudyReminders {
  StudyReminders._();

  static final instance = StudyReminders._();

  static const _enabledKey = 'study_reminders_enabled';
  static const _minutesKey = 'study_reminders_minutes';
  static const defaultTime = TimeOfDay(hour: 19, minute: 0);

  /// Notification ids 100..106: one per day of the scheduled week.
  static const _firstId = 100;
  static const _days = 7;

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  final enabled = ValueNotifier<bool>(false);
  final time = ValueNotifier<TimeOfDay>(defaultTime);

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialised = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(_enabledKey) ?? false;
    final minutes = prefs.getInt(_minutesKey);
    if (minutes != null) time.value = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
  }

  Future<void> _init() async {
    if (_initialised) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_study')),
    );
    _initialised = true;
  }

  /// Asks for notification permission (Android 13+) and, if granted, turns
  /// reminders on. Returns false when the student declined.
  Future<bool> enable() async {
    if (!supported) return false;
    await _init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission() ?? true;
    if (!granted) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, true);
    enabled.value = true;
    await refresh();
    return true;
  }

  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);
    enabled.value = false;
    if (!supported) return;
    await _init();
    await _cancelAll();
  }

  Future<void> setTime(TimeOfDay value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_minutesKey, value.hour * 60 + value.minute);
    time.value = value;
    await refresh();
  }

  /// Reschedules the coming week. Called by Home after each load with real
  /// numbers; also after a settings change, without them.
  Future<void> refresh({int dueCards = 0, int streak = 0, bool studiedToday = false}) async {
    if (!supported || !enabled.value) return;
    await _init();
    await _cancelAll();
    final slots = planReminders(
      now: DateTime.now(),
      time: time.value,
      dueCards: dueCards,
      streak: streak,
      studiedToday: studiedToday,
      days: _days,
    );
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'study_reminders',
        'Study reminders',
        channelDescription: 'Your daily nudge to study, at the time you chose in Profile',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    );
    for (var i = 0; i < slots.length; i++) {
      await _plugin.zonedSchedule(
        id: _firstId + i,
        // A local DateTime is an absolute instant, so UTC is exact here.
        scheduledDate: tz.TZDateTime.from(slots[i].at, tz.UTC),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: slots[i].title,
        body: slots[i].body,
      );
    }
  }

  Future<void> _cancelAll() async {
    for (var i = 0; i < _days; i++) {
      await _plugin.cancel(id: _firstId + i);
    }
  }
}

class ReminderSlot {
  const ReminderSlot(this.at, this.title, this.body);

  final DateTime at;
  final String title;
  final String body;
}

/// The coming week's reminders at [time] each day: today's only if that
/// time is still ahead and the student hasn't studied yet. The first one
/// uses the real streak and cards due; the rest are general, since those
/// numbers will have changed by then.
List<ReminderSlot> planReminders({
  required DateTime now,
  required TimeOfDay time,
  required int dueCards,
  required int streak,
  required bool studiedToday,
  int days = 7,
}) {
  final slots = <ReminderSlot>[];
  for (var d = 0; slots.length < days && d <= days; d++) {
    final at = DateTime(now.year, now.month, now.day + d, time.hour, time.minute);
    if (d == 0 && (studiedToday || !at.isAfter(now))) continue;
    final first = slots.isEmpty;
    final (title, body) = first
        ? _firstMessage(dueCards: dueCards, streak: streak, today: d == 0)
        : ('Time for a quick study session', 'A few minutes with Sage today keeps what you learnt fresh.');
    slots.add(ReminderSlot(at, title, body));
  }
  return slots;
}

(String, String) _firstMessage({required int dueCards, required int streak, required bool today}) {
  final cards = dueCards == 1 ? '1 flashcard is' : '$dueCards flashcards are';
  if (streak > 0 && today) {
    return (
      'Your $streak-day streak ends tonight',
      dueCards > 0 ? '$cards due — a quick review keeps it going.' : 'Answer a few questions to keep it going.',
    );
  }
  if (streak > 0) {
    return (
      'Keep your $streak-day streak going',
      dueCards > 0 ? '$cards due for review.' : 'Sage has questions ready for you.',
    );
  }
  return (
    'Time for a quick study session',
    dueCards > 0 ? '$cards due for review.' : 'Sage has questions ready for you.',
  );
}
