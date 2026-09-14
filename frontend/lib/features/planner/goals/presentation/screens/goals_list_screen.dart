import 'package:flutter/material.dart';

import '../../../../../core/api/api_client.dart';

/// Study goals (blueprint Section 22) — create/delete only this slice,
/// matching the backend's own CRUD surface (there's no PATCH /goals/{id}
/// endpoint to call). Same 4-branch list pattern as ProjectsListScreen.
class GoalsListScreen extends StatefulWidget {
  const GoalsListScreen({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  State<GoalsListScreen> createState() => _GoalsListScreenState();
}

class _GoalsListScreenState extends State<GoalsListScreen> {
  List<dynamic>? _goals;
  List<dynamic>? _projects; // for the optional knowledge-space picker
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
      final results = await Future.wait([widget.apiClient.listGoals(), widget.apiClient.listProjects()]);
      setState(() {
        _goals = results[0]['goals'] as List<dynamic>;
        _projects = results[1]['projects'] as List<dynamic>;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Goal.public() returns `knowledge_space_id` (KnowledgeSpace's internal
  /// numeric id, not its slug) — listProjects() includes that same `id`
  /// alongside `slug`/`display_name`, so this matches on it directly.
  String? _projectNameForId(int? knowledgeSpaceId) {
    if (knowledgeSpaceId == null || _projects == null) return null;
    for (final project in _projects!) {
      final p = project as Map<String, dynamic>;
      if (p['id'] == knowledgeSpaceId) return p['display_name'] as String;
    }
    return null;
  }

  Future<void> _createGoal() async {
    final titleController = TextEditingController();
    DateTime? targetDate;
    String? projectSlug;

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New goal'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Pass Fluid Mechanics finals'),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(targetDate == null ? 'No target date' : targetDate!.toLocal().toString().split(' ')[0]),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                  );
                  if (picked != null) setDialogState(() => targetDate = picked);
                },
              ),
              if (_projects != null && _projects!.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: projectSlug,
                  decoration: const InputDecoration(labelText: 'Project (optional)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Account-wide')),
                    for (final project in _projects!)
                      DropdownMenuItem(
                        value: (project as Map<String, dynamic>)['slug'] as String,
                        child: Text(project['display_name'] as String),
                      ),
                  ],
                  onChanged: (value) => setDialogState(() => projectSlug = value),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Create')),
          ],
        ),
      ),
    );
    if (created != true || titleController.text.trim().isEmpty) return;

    try {
      await widget.apiClient.createGoal(
        title: titleController.text.trim(),
        targetDate: targetDate,
        knowledgeSpaceSlug: projectSlug,
      );
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _deleteGoal(int id, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete goal?'),
        content: Text('This permanently deletes "$title".'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await widget.apiClient.deleteGoal(id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(onPressed: _createGoal, child: const Icon(Icons.add)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Builder(
          builder: (context) {
            if (_isLoading && _goals == null) {
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
            final goals = _goals ?? [];
            if (goals.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('No goals yet. Tap + to set one.')),
                  ),
                ],
              );
            }
            return ListView.builder(
              itemCount: goals.length,
              itemBuilder: (context, index) {
                final goal = goals[index] as Map<String, dynamic>;
                final id = goal['id'] as int;
                final title = goal['title'] as String;
                final targetDate = goal['target_date'] as String?;
                final projectName = _projectNameForId(goal['knowledge_space_id'] as int?);
                final subtitleParts = [
                  if (targetDate != null) 'Due ${DateTime.parse(targetDate).toLocal().toString().split(' ')[0]}',
                  if (projectName != null) projectName,
                ];
                return ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: Text(title),
                  subtitle: subtitleParts.isEmpty ? null : Text(subtitleParts.join(' · ')),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteGoal(id, title),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
