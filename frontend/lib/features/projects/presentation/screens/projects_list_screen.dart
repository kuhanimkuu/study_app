import 'package:flutter/material.dart';

import '../../../../core/api/api_client.dart';
import 'project_workspace_screen.dart';

/// Home screen for "notebooks" — see server/db.py's module docstring for
/// why projects are the one thing this client stores server-side rather
/// than on-device. Each project opens into ProjectWorkspaceScreen (Sources
/// + Chat tabs; a Studio tab for generated artifacts is deliberately not
/// built yet — see that screen's doc comment).
class ProjectsListScreen extends StatefulWidget {
  const ProjectsListScreen({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  State<ProjectsListScreen> createState() => _ProjectsListScreenState();
}

class _ProjectsListScreenState extends State<ProjectsListScreen> {
  List<dynamic>? _projects;
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
      final result = await widget.apiClient.listProjects();
      setState(() => _projects = result['projects'] as List<dynamic>);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createProject() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New project'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Thermodynamics'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;

    try {
      await widget.apiClient.createProject(displayName: name.trim());
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _deleteProject(String slug, String displayName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete project?'),
        content: Text('This permanently deletes "$displayName" and all of its stored material.'),
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
      await widget.apiClient.deleteProject(slug);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Projects')),
      floatingActionButton: FloatingActionButton(onPressed: _createProject, child: const Icon(Icons.add)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Builder(
          builder: (context) {
            if (_isLoading && _projects == null) {
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
            final projects = _projects ?? [];
            if (projects.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text('No projects yet. Tap + to create one and add material to it.'),
                    ),
                  ),
                ],
              );
            }
            return ListView.builder(
              itemCount: projects.length,
              itemBuilder: (context, index) {
                final project = projects[index] as Map<String, dynamic>;
                final slug = project['slug'] as String;
                final displayName = project['display_name'] as String;
                final chunkCount = project['chunk_count'] as int? ?? 0;
                return ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(displayName),
                  subtitle: Text(chunkCount == 0 ? 'No material yet' : '$chunkCount stored chunk(s)'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteProject(slug, displayName),
                  ),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => ProjectWorkspaceScreen(
                          apiClient: widget.apiClient,
                          slug: slug,
                          displayName: displayName,
                        ),
                      ),
                    );
                    _load(); // chunk_count may have changed while the workspace was open
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
