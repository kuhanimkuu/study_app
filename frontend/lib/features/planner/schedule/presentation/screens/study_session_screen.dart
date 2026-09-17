import 'package:flutter/material.dart';

import '../../../../../core/api/api_client.dart';
import '../../../../tutor/sessions/presentation/screens/guided_session_runner_screen.dart';

/// Renders one generated plan's phases — shared by StudyPlanScreen (a plan
/// not yet saved as a session) and StudySessionScreen (a saved session's
/// stored plan) so the phase layout can't drift between the two.
class PlanPhasesView extends StatelessWidget {
  const PlanPhasesView({super.key, required this.plan});

  final Map<String, dynamic> plan;

  static const _phaseLabels = {
    'retrieval_practice': 'Retrieval practice',
    'focus_weak_concepts': 'Focus on weak concepts',
    'practice': 'Practice',
    'reflection': 'Reflection',
  };

  @override
  Widget build(BuildContext context) {
    final phases = plan['phases'] as List<dynamic>;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final phase in phases)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _phaseLabels[(phase as Map<String, dynamic>)['phase']] ?? phase['phase'] as String,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text('${phase['duration_minutes']} min', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final concepts = phase['concepts'] as List<dynamic>? ?? [];
                      if (concepts.isEmpty) {
                        return Text(
                          'No concepts in this phase.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                        );
                      }
                      return Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final concept in concepts)
                            Chip(label: Text((concept as Map<String, dynamic>)['name'] as String)),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// One StudySession — its stored plan (rendered via PlanPhasesView) plus a
/// "Mark complete" action.
class StudySessionScreen extends StatefulWidget {
  const StudySessionScreen({super.key, required this.apiClient, required this.session});

  final ApiClient apiClient;
  final Map<String, dynamic> session;

  @override
  State<StudySessionScreen> createState() => _StudySessionScreenState();
}

class _StudySessionScreenState extends State<StudySessionScreen> {
  late Map<String, dynamic> _session = widget.session;
  bool _isCompleting = false;
  String? _error;

  Future<void> _complete() async {
    setState(() {
      _isCompleting = true;
      _error = null;
    });
    try {
      final updated = await widget.apiClient.completeStudySession(_session['id'] as int);
      setState(() => _session = updated);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isCompleting = false);
    }
  }

  Future<void> _startGuided() async {
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => GuidedSessionRunnerScreen(apiClient: widget.apiClient, session: _session),
      ),
    );
    if (completed == true) {
      // The runner already called completeStudySession — refetch this
      // screen's copy so its own "Active"/"Completed" banner matches.
      try {
        final refreshed = await widget.apiClient.getStudySession(_session['id'] as int);
        if (mounted) setState(() => _session = refreshed);
      } catch (_) {
        // non-critical — worst case this screen's banner is one refresh stale
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _session['status'] as String;
    final isCompleted = status == 'completed';
    final plan = _session['plan'] as Map<String, dynamic>;

    return Scaffold(
      appBar: AppBar(title: const Text('Study session')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Icon(
                isCompleted ? Icons.check_circle : Icons.play_circle_outline,
                color: isCompleted ? Colors.green : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(isCompleted ? 'Completed' : 'Active', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 16),
          PlanPhasesView(plan: plan),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          if (!isCompleted) ...[
            FilledButton.icon(
              onPressed: _startGuided,
              icon: const Icon(Icons.school_outlined),
              label: const Text('Start guided session'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _isCompleting ? null : _complete,
              child: _isCompleting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Mark complete'),
            ),
          ],
        ],
      ),
    );
  }
}
