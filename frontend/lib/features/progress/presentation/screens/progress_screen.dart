import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/api/api_client.dart';
import '../../../planner/schedule/presentation/screens/study_session_screen.dart';

/// Mastery/weak-spots overview + a merged recent-activity feed + Insights
/// (blueprint Section 39). One screen, not split into dashboard/history/
/// insights sub-screens — avoids a tab-inside-tab layout under the
/// Planner tab's own TabBar.
///
/// Insights (streak, this-week accuracy, weekly activity chart) are
/// derived entirely client-side from `_activity` — no new backend
/// endpoint or stored history needed, since GET /api/v1/attempts and
/// GET /api/v1/study-sessions already carry real timestamps. A genuine
/// mastery-trend-over-time chart would need periodic snapshots this
/// project doesn't store yet — deliberately not attempted; these
/// insights are honestly derivable from what already exists, not a
/// stand-in for that.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  List<dynamic>? _mastery;
  List<dynamic>? _misconceptions;
  List<Map<String, dynamic>>? _activity; // merged sessions + attempts, each tagged with '_kind'
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.apiClient.getMastery(),
        widget.apiClient.getMisconceptions(),
        widget.apiClient.listStudySessions(),
        widget.apiClient.getAttempts(),
      ]);
      final mastery = (results[0]['mastery'] as List<dynamic>).cast<Map<String, dynamic>>()
        ..sort((a, b) => (a['mastery'] as num).compareTo(b['mastery'] as num)); // weakest first

      final sessions = (results[2]['study_sessions'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((s) => {...s, '_kind': 'session', '_timestamp': s['created_at']});
      final attempts = (results[3]['attempts'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((a) => {...a, '_kind': 'attempt', '_timestamp': a['created_at']});
      final activity = [...sessions, ...attempts]
        ..sort((a, b) => (b['_timestamp'] as String).compareTo(a['_timestamp'] as String));

      setState(() {
        _mastery = mastery;
        _misconceptions = results[1]['misconceptions'] as List<dynamic>;
        _activity = activity;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openSession(Map<String, dynamic> session) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => StudySessionScreen(apiClient: widget.apiClient, session: session),
      ),
    );
    _load(); // status may have changed (e.g. marked complete) while open
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: Builder(
        builder: (context) {
          if (_isLoading && _mastery == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_error != null) {
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Mastery & weak spots', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if ((_mastery ?? []).isEmpty)
                const Text('No concepts attempted yet.')
              else
                for (final m in _mastery!) _MasteryRow(item: m),
              if ((_misconceptions ?? []).isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Needs attention', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                for (final m in _misconceptions!)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: ListTile(
                      leading: const Icon(Icons.warning_amber_outlined),
                      title: Text(m['concept_name'] as String),
                      subtitle: Text(m['description'] as String),
                    ),
                  ),
              ],
              if ((_activity ?? []).isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Insights', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _InsightsSection(activity: _activity!),
              ],
              const SizedBox(height: 24),
              Text('Recent activity', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if ((_activity ?? []).isEmpty)
                const Text('No study sessions or practice attempts yet.')
              else
                for (final item in _activity!) _ActivityRow(item: item, onOpenSession: _openSession),
            ],
          );
        },
      ),
    );
  }
}

class _MasteryRow extends StatelessWidget {
  const _MasteryRow({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final mastery = (item['mastery'] as num).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['concept_name'] as String),
                const SizedBox(height: 4),
                LinearProgressIndicator(value: mastery, minHeight: 6),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text('${(mastery * 100).round()}%'),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item, required this.onOpenSession});

  final Map<String, dynamic> item;
  final void Function(Map<String, dynamic>) onOpenSession;

  @override
  Widget build(BuildContext context) {
    final timestamp = DateTime.parse(item['_timestamp'] as String).toLocal();
    final timeLabel = timestamp.toString().split('.').first;

    if (item['_kind'] == 'session') {
      final status = item['status'] as String;
      return Card(
        child: ListTile(
          leading: Icon(status == 'completed' ? Icons.check_circle_outline : Icons.play_circle_outline),
          title: Text('Study session (${item['planned_duration_minutes']} min) — $status'),
          subtitle: Text(timeLabel),
          onTap: () => onOpenSession(item),
        ),
      );
    }

    final isCorrect = item['is_correct'] as bool;
    return Card(
      child: ListTile(
        leading: Icon(
          isCorrect ? Icons.check_circle_outline : Icons.cancel_outlined,
          color: isCorrect ? Colors.green : Theme.of(context).colorScheme.error,
        ),
        title: Text(item['concept_name'] as String),
        subtitle: Text('${item['question_prompt']}\n$timeLabel'),
        isThreeLine: true,
      ),
    );
  }
}

/// Streak / this-week-accuracy / weekly-activity-chart, all derived from
/// the same merged activity feed the "Recent activity" section already
/// renders — see this file's header comment for why nothing new was
/// added to the backend for this.
class _InsightsSection extends StatelessWidget {
  const _InsightsSection({required this.activity});

  final List<Map<String, dynamic>> activity;

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  Set<DateTime> get _activeDays =>
      activity.map((a) => _dateOnly(DateTime.parse(a['_timestamp'] as String).toLocal())).toSet();

  int get _streak {
    var streak = 0;
    var day = _dateOnly(DateTime.now());
    final active = _activeDays;
    while (active.contains(day)) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  List<Map<String, dynamic>> get _attemptsThisWeek {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return activity
        .where((a) => a['_kind'] == 'attempt' && DateTime.parse(a['_timestamp'] as String).toLocal().isAfter(cutoff))
        .toList();
  }

  /// Oldest-to-newest counts of attempts per day for the last 7 days
  /// (including today) — index 0 is 6 days ago, index 6 is today.
  List<int> get _dailyAttemptCounts {
    final today = _dateOnly(DateTime.now());
    final counts = List<int>.filled(7, 0);
    for (final a in activity) {
      if (a['_kind'] != 'attempt') continue;
      final day = _dateOnly(DateTime.parse(a['_timestamp'] as String).toLocal());
      final offset = today.difference(day).inDays;
      if (offset >= 0 && offset < 7) counts[6 - offset]++;
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    final weekAttempts = _attemptsThisWeek;
    final weekCorrect = weekAttempts.where((a) => a['is_correct'] as bool).length;
    final accuracyLabel = weekAttempts.isEmpty ? '—' : '${((weekCorrect / weekAttempts.length) * 100).round()}%';
    final counts = _dailyAttemptCounts;
    final maxCount = counts.fold<int>(1, (m, c) => c > m ? c : m);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _StatTile(label: 'Study streak', value: '$_streak day(s)')),
                Expanded(child: _StatTile(label: 'This week', value: '$accuracyLabel accuracy')),
              ],
            ),
            const SizedBox(height: 16),
            Text('Practice attempts, last 7 days', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            SizedBox(
              height: 100,
              child: BarChart(
                BarChartData(
                  maxY: maxCount.toDouble() + 1,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: const FlTitlesData(
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  barGroups: [
                    for (int i = 0; i < counts.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: counts[i].toDouble(),
                            color: Theme.of(context).colorScheme.primary,
                            width: 18,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}
