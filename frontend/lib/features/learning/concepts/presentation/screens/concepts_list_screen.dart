import 'package:flutter/material.dart';

import '../../../../../app/theme.dart';
import '../../../../../core/api/api_client.dart';
import '../../../../../core/widgets/ai_generate_button.dart';
import '../../../../../core/widgets/mastery_ring.dart';
import '../../../../../core/widgets/tab_kit.dart';
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

  Widget _generateButton({bool expand = false}) => AiGenerateButton(
        label: 'Find concepts in my sources',
        expand: expand,
        onGenerate: () async =>
            generatedSummary(await widget.apiClient.generateConcepts(widget.slug), 'concepts', 'concept'),
        onDone: _load,
      );

  Future<void> _openConcept(Map<String, dynamic> concept) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ConceptDetailScreen(
          apiClient: widget.apiClient,
          concept: concept,
          knowledgeSpaceSlug: widget.slug,
        ),
      ),
    );
    _load(); // mastery may have changed while the detail screen was open
  }

  /// Where a concept stands, in words a student uses.
  static ({String label, Color color, IconData icon}) _stage(double? mastery) {
    if (mastery == null || mastery < 0.01) return (label: 'New', color: StudyOsColors.xp, icon: Icons.fiber_new_rounded);
    if (mastery < 0.5) return (label: 'Learning', color: StudyOsColors.streak, icon: Icons.trending_up_rounded);
    if (mastery < 0.75) return (label: 'Getting there', color: StudyOsColors.amber, icon: Icons.bolt_rounded);
    return (label: 'Strong', color: StudyOsColors.success, icon: Icons.verified_rounded);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final concepts = (_concepts ?? []).cast<Map<String, dynamic>>();
    final known = concepts.map((c) => _masteryById[c['id'] as int]).whereType<double>().toList();
    final average = known.isEmpty ? 0.0 : known.reduce((a, b) => a + b) / known.length;
    final strong = known.where((m) => m >= 0.75).length;

    Widget body;
    if (_isLoading && _concepts == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [Text(_error!, style: TextStyle(color: theme.colorScheme.error))],
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          const TabIntro(
            title: 'Concepts',
            subtitle: 'The big ideas in this subject, and how well you know each one.',
          ),
          if (concepts.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatChip(icon: Icons.lightbulb_rounded, value: '${concepts.length}', label: concepts.length == 1 ? 'concept' : 'concepts', color: StudyOsColors.primary),
                StatChip(icon: Icons.verified_rounded, value: '$strong', label: 'strong', color: StudyOsColors.success),
                StatChip(icon: Icons.insights_rounded, value: '${(average * 100).round()}%', label: 'average', color: StudyOsColors.xp),
              ],
            ),
          ],
          const SizedBox(height: 16),
          SageActionCard(
            title: concepts.isEmpty ? 'Let me find the key ideas' : 'Missing something?',
            body: concepts.isEmpty
                ? 'I can read this subject\'s sources and pull out the concepts worth learning. Or tap + to add one yourself.'
                : 'I can look through your sources again for concepts not on this list yet.',
            action: _generateButton(),
          ),
          const SizedBox(height: 18),
          if (concepts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Icon(Icons.lightbulb_outline_rounded, size: 52, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35)),
                  const SizedBox(height: 8),
                  Text('No concepts yet', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            )
          else
            for (final concept in concepts) ...[
              _conceptCard(context, concept),
              const SizedBox(height: 10),
            ],
        ],
      );
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createConcept,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New concept'),
      ),
      body: RefreshIndicator(onRefresh: _load, child: body),
    );
  }

  Widget _conceptCard(BuildContext context, Map<String, dynamic> concept) {
    final theme = Theme.of(context);
    final mastery = _masteryById[concept['id'] as int];
    final stage = _stage(mastery);
    final description = (concept['description'] as String?)?.trim() ?? '';
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openConcept(concept),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: Row(
            children: [
              mastery == null
                  ? IconBadge(icon: Icons.lightbulb_rounded, color: stage.color, size: 46)
                  : MasteryRing(mastery: mastery, size: 46),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      concept['name'] as String,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TagPill(label: stage.label, color: stage.color, icon: stage.icon),
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

// Avoids pulling in dart:async just for this one unawaited() call.
void unawaited(Future<void> future) {}
