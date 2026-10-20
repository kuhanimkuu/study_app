import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

/// Home's exam countdown (2026-10-20): the nearest upcoming goal with a
/// date (Plan → Goals). The planner already puts subjects with a nearer
/// deadline first (planning/planner.py's build_plan); this makes that
/// deadline visible.

/// The goal with the soonest target date from today on, with whole days
/// left (0 = today), or null if none is upcoming.
({Map<String, dynamic> goal, int daysLeft})? nextExam(List<Map<String, dynamic>> goals, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  ({Map<String, dynamic> goal, int daysLeft})? best;
  for (final goal in goals) {
    final at = DateTime.tryParse(goal['target_date'] as String? ?? '')?.toLocal();
    if (at == null) continue;
    final days = DateTime(at.year, at.month, at.day).difference(today).inDays;
    if (days < 0) continue;
    if (best == null || days < best.daysLeft) best = (goal: goal, daysLeft: days);
  }
  return best;
}

String daysLeftLabel(int days) => switch (days) {
      0 => 'Today',
      1 => 'Tomorrow',
      _ => 'In $days days',
    };

class ExamCountdownCard extends StatelessWidget {
  const ExamCountdownCard({super.key, required this.title, required this.daysLeft, this.onOpen});

  final String title;
  final int daysLeft;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final urgent = daysLeft <= 7;
    final color = urgent ? StudyOsColors.streak : StudyOsColors.primary;
    final radius = BorderRadius.circular(18);
    return Material(
      color: color.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: color.withValues(alpha: 0.4), width: 1.5)),
      child: InkWell(
        borderRadius: radius,
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
                alignment: Alignment.center,
                child: daysLeft <= 1
                    ? const Icon(Icons.event_rounded, color: Colors.white, size: 26)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('$daysLeft', style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, height: 1)),
                          Text('days', style: theme.textTheme.labelSmall?.copyWith(color: Colors.white)),
                        ],
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(daysLeftLabel(daysLeft), style: theme.textTheme.labelMedium?.copyWith(color: color)),
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                    Text(
                      urgent ? 'Your study plan is putting this first.' : 'Your study plan is counting down to this.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
