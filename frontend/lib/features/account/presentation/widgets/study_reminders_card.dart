import 'package:flutter/material.dart';

import '../../../../core/notifications/study_reminders.dart';

/// Profile → "Study reminders": off until the student turns it on (which is
/// when Android asks for notification permission), plus the time of day.
class StudyRemindersCard extends StatefulWidget {
  const StudyRemindersCard({super.key, StudyReminders? reminders}) : _reminders = reminders;

  final StudyReminders? _reminders;

  @override
  State<StudyRemindersCard> createState() => _StudyRemindersCardState();
}

class _StudyRemindersCardState extends State<StudyRemindersCard> with WidgetsBindingObserver {
  StudyReminders get _reminders => widget._reminders ?? StudyReminders.instance;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from Android's "Alarms & reminders" page: pick up the new setting.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reminders.recheckExactTiming();
  }

  Future<void> _toggle(bool on) async {
    setState(() => _busy = true);
    if (on) {
      final granted = await _reminders.enable();
      if (!granted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notifications are blocked for Study OS. Allow them in your phone\'s Settings → Apps → Study OS.'),
          ),
        );
      }
    } else {
      await _reminders.disable();
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _reminders.time.value);
    if (picked != null) await _reminders.setTime(picked);
  }

  @override
  Widget build(BuildContext context) {
    if (!StudyReminders.supported) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ValueListenableBuilder<bool>(
        valueListenable: _reminders.enabled,
        builder: (context, enabled, _) => ValueListenableBuilder<TimeOfDay>(
          valueListenable: _reminders.time,
          builder: (context, time, _) => Column(
            children: [
              SwitchListTile(
                secondary: Icon(Icons.notifications_active_outlined, color: theme.colorScheme.primary),
                title: const Text('Study reminders'),
                subtitle: Text(
                  enabled
                      ? 'A daily nudge with your streak and cards due. Skipped on days you\'ve already studied.'
                      : 'Off. Turn on for a daily nudge to keep your streak.',
                ),
                value: enabled,
                onChanged: _busy ? null : _toggle,
              ),
              if (enabled)
                ListTile(
                  leading: const SizedBox(width: 24),
                  title: const Text('Remind me at'),
                  trailing: Text(time.format(context), style: theme.textTheme.titleSmall),
                  onTap: _pickTime,
                ),
              if (enabled)
                ValueListenableBuilder<bool>(
                  valueListenable: _reminders.exact,
                  builder: (context, exact, _) => exact
                      ? const SizedBox.shrink()
                      : ListTile(
                          leading: const SizedBox(width: 24),
                          title: const Text('Arrive at the exact minute'),
                          subtitle: const Text(
                            'Android may delay reminders by a few minutes. Allow "Alarms & reminders" to get them on time.',
                          ),
                          trailing: TextButton(
                            onPressed: _busy ? null : _reminders.requestExactTiming,
                            child: const Text('Allow'),
                          ),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
