import 'package:flutter/material.dart';

import '../../../../../core/api/api_client.dart';
import 'concept_detail_screen.dart';

/// Concepts within one Knowledge Space (blueprint Section 15) — a new 4th
/// tab on ProjectWorkspaceScreen, not a new top-level nav destination (see
/// STUDY_OS_PROGRESS.md's 2026-09-14 frontend entry for why). Same
/// loading/error/empty/list shape as ProjectsListScreen.
class ConceptsListScreen extends StatefulWidget {
  const ConceptsListScreen({super.key, required this.apiClient, required this.slug});

  final ApiClient apiClient;
  final String slug;

  @override
  State<ConceptsListScreen> createState() => _ConceptsListScreenState();
}

class _ConceptsListScreenState extends State<ConceptsListScreen> {
  List<dynamic>? _concepts;
  // Mastery is fetched per-concept (there's no "list mastery for a space"
  // endpoint, only "list mastery for a user" — see server/domains/
  // learning/router.py) and cached here by concept id so the list doesn't
  // re-fetch it every rebuild.
  final Map<int, double> _masteryById = {};
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
      final result = await widget.apiClient.listConcepts(widget.slug);
      final concepts = result['concepts'] as List<dynamic>;
      setState(() => _concepts = concepts);
      for (final concept in concepts) {
        final id = (concept as Map<String, dynamic>)['id'] as int;
        unawaited(_loadMastery(id));
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMastery(int conceptId) async {
    try {
      final result = await widget.apiClient.getConceptMastery(conceptId);
      final mastery = (result['mastery'] as num).toDouble();
      if (mounted) setState(() => _masteryById[conceptId] = mastery);
    } catch (_) {
      // Non-critical — the list row just shows no mastery badge for this one.
    }
  }

  Future<void> _createConcept() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New concept'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Bernoulli Equation'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(nameController.text), child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;

    try {
      await widget.apiClient.createConcept(
        slug: widget.slug,
        name: name.trim(),
        description: descriptionController.text.trim().isEmpty ? null : descriptionController.text.trim(),
      );
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
      floatingActionButton: FloatingActionButton(onPressed: _createConcept, child: const Icon(Icons.add)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Builder(
          builder: (context) {
            if (_isLoading && _concepts == null) {
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
            final concepts = _concepts ?? [];
            if (concepts.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('No concepts yet. Tap + to add one.')),
                  ),
                ],
              );
            }
            return ListView.builder(
              itemCount: concepts.length,
              itemBuilder: (context, index) {
                final concept = concepts[index] as Map<String, dynamic>;
                final id = concept['id'] as int;
                final name = concept['name'] as String;
                final mastery = _masteryById[id];
                return ListTile(
                  leading: const Icon(Icons.school_outlined),
                  title: Text(name),
                  subtitle: mastery == null
                      ? null
                      : LinearProgressIndicator(value: mastery, minHeight: 4),
                  trailing: mastery == null
                      ? null
                      : Text('${(mastery * 100).round()}%', style: Theme.of(context).textTheme.labelSmall),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => ConceptDetailScreen(apiClient: widget.apiClient, concept: concept),
                      ),
                    );
                    _load(); // mastery may have changed while the detail screen was open
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

// Avoids pulling in dart:async just for this one unawaited() call.
void unawaited(Future<void> future) {}
