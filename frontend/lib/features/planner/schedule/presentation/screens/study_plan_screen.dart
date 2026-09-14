import 'package:flutter/material.dart';

import '../../../../../core/api/api_client.dart';
import 'study_session_screen.dart';

/// Generates and shows a prioritized study plan (blueprint Section 21-22)
/// — "What should I study right now?" — and lets the student turn it into
/// a real StudySession. No typed models: plan/session stay raw JSON, same
/// convention as every other screen.
class StudyPlanScreen extends StatefulWidget {
  const StudyPlanScreen({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  State<StudyPlanScreen> createState() => _StudyPlanScreenState();
}

class _StudyPlanScreenState extends State<StudyPlanScreen> {
  static const _durationOptions = [30, 60, 90, 120];

  int _durationMinutes = 60;
  String? _projectSlug;
  List<dynamic>? _projects;

  Map<String, dynamic>? _plan;
  bool _isLoadingProjects = false;
  bool _isGenerating = false;
  bool _isStarting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    setState(() => _isLoadingProjects = true);
    try {
      final result = await widget.apiClient.listProjects();
      setState(() => _projects = result['projects'] as List<dynamic>);
    } catch (_) {
      // non-critical — the project-scope dropdown just starts empty
    } finally {
      if (mounted) setState(() => _isLoadingProjects = false);
    }
  }

  Future<void> _generatePlan() async {
    setState(() {
      _isGenerating = true;
      _error = null;
    });
    try {
      final plan = await widget.apiClient.getPlan(
        durationMinutes: _durationMinutes,
        knowledgeSpaceSlug: _projectSlug,
      );
      setState(() => _plan = plan);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _startSession() async {
    setState(() {
      _isStarting = true;
      _error = null;
    });
    try {
      final session = await widget.apiClient.createStudySession(
        durationMinutes: _durationMinutes,
        knowledgeSpaceSlug: _projectSlug,
      );
      if (mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => StudySessionScreen(apiClient: widget.apiClient, session: session),
          ),
        );
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final concepts = (_plan?['concepts_considered'] as int?) ?? 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Duration', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final minutes in _durationOptions)
              ChoiceChip(
                label: Text('$minutes min'),
                selected: _durationMinutes == minutes,
                onSelected: (_) => setState(() => _durationMinutes = minutes),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Scope', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          initialValue: _projectSlug,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: [
            const DropdownMenuItem(value: null, child: Text('All projects')),
            if (_projects != null)
              for (final project in _projects!)
                DropdownMenuItem(
                  value: (project as Map<String, dynamic>)['slug'] as String,
                  child: Text(project['display_name'] as String),
                ),
          ],
          onChanged: _isLoadingProjects ? null : (value) => setState(() => _projectSlug = value),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _isGenerating ? null : _generatePlan,
          icon: _isGenerating
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.auto_awesome),
          label: const Text('Generate plan'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        if (_plan != null) ...[
          const SizedBox(height: 16),
          Text(
            concepts == 0 ? 'No concepts to plan yet — add some in a project first.' : '$concepts concept(s) considered',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          PlanPhasesView(plan: _plan!),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _isStarting ? null : _startSession,
            child: _isStarting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Start this session'),
          ),
        ],
      ],
    );
  }
}
