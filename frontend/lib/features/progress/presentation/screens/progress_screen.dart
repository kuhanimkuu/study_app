import 'package:flutter/material.dart';

import '../../../../core/api/api_client.dart';
import '../../../planner/schedule/presentation/screens/study_session_screen.dart';

/// Mastery/weak-spots overview + a merged recent-activity feed (blueprint
/// Section 39). One screen, not split into dashboard/history/insights sub-
/// screens — avoids a tab-inside-tab layout under the Planner tab's own
/// TabBar. "Insights" (trend analysis) is deliberately not built this pass.
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
