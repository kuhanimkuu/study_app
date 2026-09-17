import 'package:flutter/material.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_item_card.dart';

/// Explicit memory (blueprint Sections 8-9) — facts/preferences the
/// student states directly ("explain things using sailing analogies").
/// Create/list/delete only, matching the backend's own CRUD surface (no
/// PATCH endpoint, and episodic memories are system-generated — not
/// creatable here). Same 4-branch list pattern as every other list screen.
class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  List<dynamic>? _memories;
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
      final result = await widget.apiClient.listMemories(type: 'explicit');
      setState(() => _memories = result['memories'] as List<dynamic>);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createMemory() async {
    final keyController = TextEditingController();
    final valueController = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New memory'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Key', hintText: 'e.g. explanation_style'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: valueController,
              decoration: const InputDecoration(labelText: 'Value', hintText: 'e.g. use sailing analogies'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Create')),
        ],
      ),
    );
    if (created != true || keyController.text.trim().isEmpty || valueController.text.trim().isEmpty) return;

    try {
      await widget.apiClient.createMemory(key: keyController.text.trim(), value: valueController.text.trim());
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _deleteMemory(int id) async {
    try {
      await widget.apiClient.deleteMemory(id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Memory')),
      floatingActionButton: FloatingActionButton(onPressed: _createMemory, child: const Icon(Icons.add)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Builder(
          builder: (context) {
            if (_isLoading && _memories == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (_error != null) {
              return ListView(
                children: [
                  EmptyState(icon: Icons.error_outline, message: _error!, iconColor: Theme.of(context).colorScheme.error),
                ],
              );
            }
            final memories = _memories ?? [];
            if (memories.isEmpty) {
              return ListView(
                children: const [
                  EmptyState(icon: Icons.psychology_outlined, message: 'No stated preferences yet. Tap + to add one.'),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: memories.length,
              itemBuilder: (context, index) {
                final memory = memories[index] as Map<String, dynamic>;
                return ListItemCard(
                  icon: Icons.psychology_outlined,
                  title: memory['key'] as String,
                  subtitle: memory['value'].toString(),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteMemory(memory['id'] as int),
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
