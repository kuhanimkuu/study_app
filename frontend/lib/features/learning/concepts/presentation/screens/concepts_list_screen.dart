import 'package:flutter/material.dart';

import '../../../../../app/theme.dart';
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
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.school_outlined, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                          const SizedBox(height: 16),
                          Text(
                            'No concepts yet. Tap + to add one.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: concepts.length,
              itemBuilder: (context, index) {
                final concept = concepts[index] as Map<String, dynamic>;
                final id = concept['id'] as int;
                final name = concept['name'] as String;
                final mastery = _masteryById[id];
                // Mastery is the one number this screen exists to move —
                // it gets its own bespoke card (icon badge tinted by
                // progress + a real progress bar + a percentage pill)
                // rather than the plain ListItemCard row every other list
                // screen uses, the same way Nexora gives its one
                // state-driven card (ElectricFlashCard) its own anatomy.
                final masteryColor = mastery == null
                    ? Theme.of(context).colorScheme.primary
                    : Color.lerp(Theme.of(context).colorScheme.primary, StudyOsColors.accent, mastery)!;
                return Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => ConceptDetailScreen(apiClient: widget.apiClient, concept: concept),
                        ),
                      );
                      _load(); // mastery may have changed while the detail screen was open
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(color: masteryColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                            child: Icon(Icons.school_outlined, color: masteryColor),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(name, style: Theme.of(context).textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                                if (mastery != null) ...[
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: mastery,
                                      minHeight: 6,
                                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                      valueColor: AlwaysStoppedAnimation(masteryColor),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (mastery != null) ...[
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: masteryColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9999)),
                              child: Text(
                                '${(mastery * 100).round()}%',
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: masteryColor, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
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

// Avoids pulling in dart:async just for this one unawaited() call.
void unawaited(Future<void> future) {}
