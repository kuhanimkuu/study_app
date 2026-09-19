import 'package:flutter/material.dart';

import '../../../../../app/theme.dart';
import '../../../../../core/api/api_client.dart';
import '../../../../../core/auth/auth_service.dart';
import '../../../../../core/widgets/empty_state.dart';
import '../../../../../core/widgets/mastery_ring.dart';
import '../../../../../core/widgets/profile_icon_button.dart';
import '../../../../practice/flashcards/presentation/screens/flashcard_review_screen.dart';
import '../../../../practice/quizzes/presentation/screens/quiz_runner_screen.dart';
import 'concept_detail_screen.dart';

/// Account-wide Learn hub — matches the approved visual reference's
/// `Learn.tsx`: mode buttons (Flashcards/Quiz/Practice), a subject filter,
/// and a concept list with a mastery ring per row. This replaces
/// "Projects" in the bottom nav's Learn-hub slot (see `app_shell.dart`'s
/// doc comment on why Projects held that slot until this slice).
///
/// Built entirely from data that already exists — no new backend
/// endpoints — since `GET /api/v1/mastery` already returns every concept's
/// name, id, and Knowledge Space slug account-wide. "Quiz" and "Practice"
/// both open a concept picker then reuse the real per-concept question set
/// and `QuizRunnerScreen`'s own `examMode` flag (Quiz = exam mode /
/// feedback at the end, Practice = immediate feedback) — real existing
/// behavior, not two new flows invented to match the mockup's 3 buttons.
///
/// **Real gap closed, found while verifying**: `GET /api/v1/mastery` only
/// returns concepts with at least one attempt (confirmed against the live
/// server, not assumed) — a brand-new concept would otherwise be invisible
/// here until practiced from somewhere else, a chicken-and-egg problem for
/// a screen whose whole job is "where you go to practice". `_load` also
/// fetches every project's own concept list (`listConcepts` per Knowledge
/// Space) and merges in any concept missing from the mastery list at a
/// real, honest 0% — not fabricated, just the correct floor value for
/// "never attempted" (same convention `planning/planner.py` already uses
/// server-side).
class LearnHubScreen extends StatefulWidget {
  const LearnHubScreen({super.key, required this.apiClient, required this.authService});

  final ApiClient apiClient;
  final AuthService authService;

  @override
  State<LearnHubScreen> createState() => _LearnHubScreenState();
}

class _LearnHubScreenState extends State<LearnHubScreen> {
  List<Map<String, dynamic>>? _mastery;
  List<dynamic>? _dueFlashcards;
  Map<String, String> _spaceNames = {}; // slug -> display_name
  String _filter = 'All';
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
        widget.apiClient.getDueFlashcards(),
        widget.apiClient.listProjects(),
      ]);
      final projects = (results[2]['projects'] as List<dynamic>).cast<Map<String, dynamic>>();
      final mastery = (results[0]['mastery'] as List<dynamic>).cast<Map<String, dynamic>>();
      final attemptedIds = mastery.map((m) => m['concept_id'] as int).toSet();

      // Fill in never-attempted concepts (missing from `mastery` entirely)
      // at a real 0% rather than leaving them undiscoverable here.
      final conceptLists = await Future.wait(
        projects.map((p) => widget.apiClient.listConcepts(p['slug'] as String)),
      );
      for (var i = 0; i < projects.length; i++) {
        final slug = projects[i]['slug'] as String;
        for (final raw in conceptLists[i]['concepts'] as List<dynamic>) {
          final concept = raw as Map<String, dynamic>;
          final id = concept['id'] as int;
          if (attemptedIds.contains(id)) continue;
          mastery.add({'concept_id': id, 'concept_name': concept['name'], 'knowledge_space_slug': slug, 'mastery': 0.0});
        }
      }

      setState(() {
        _mastery = mastery;
        _dueFlashcards = results[1]['flashcards'] as List<dynamic>;
        _spaceNames = {for (final p in projects) p['slug'] as String: p['display_name'] as String};
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openFlashcardReview() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (context) => FlashcardReviewScreen(apiClient: widget.apiClient)));
    _load();
  }

  Future<void> _pickConceptThen(bool examMode) async {
    final concepts = _mastery ?? [];
    if (concepts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No concepts yet — add one from a study space first.')));
      return;
    }
    final chosen = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(examMode ? 'Quiz which concept?' : 'Practice which concept?', style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final c in concepts)
              ListTile(
                title: Text(c['concept_name'] as String),
                subtitle: c['knowledge_space_slug'] != null ? Text(_spaceNames[c['knowledge_space_slug']] ?? c['knowledge_space_slug'] as String) : null,
                onTap: () => Navigator.of(context).pop(c),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;

    try {
      final conceptId = chosen['concept_id'] as int;
      final result = await widget.apiClient.listQuestions(conceptId);
      final questions = (result['questions'] as List<dynamic>).cast<Map<String, dynamic>>();
      if (questions.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This concept has no questions yet.')));
        return;
      }
      if (!mounted) return;
      final quizResult = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(
          builder: (context) => QuizRunnerScreen(
            apiClient: widget.apiClient,
            questions: questions,
            title: chosen['concept_name'] as String,
            examMode: examMode,
          ),
        ),
      );
      _load();
      if (quizResult != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${examMode ? 'Exam' : 'Practice'} complete: ${quizResult['correct']}/${quizResult['total']} correct')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _openConcept(Map<String, dynamic> item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ConceptDetailScreen(
          apiClient: widget.apiClient,
          concept: {'id': item['concept_id'], 'name': item['concept_name']},
          knowledgeSpaceSlug: item['knowledge_space_slug'] as String?,
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: Builder(
            builder: (context) {
              if (_isLoading && _mastery == null) {
                return const Center(child: CircularProgressIndicator());
              }
              if (_error != null) {
                return ListView(children: [Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)))]);
              }

              final mastery = _mastery ?? [];
              final subjects = ['All', ..._spaceNames.values.toSet()];
              final filtered = _filter == 'All'
                  ? mastery
                  : mastery.where((c) => _spaceNames[c['knowledge_space_slug']] == _filter).toList();
              final dueCount = (_dueFlashcards ?? []).length;

              if (mastery.isEmpty) {
                return ListView(
                  children: const [
                    EmptyState(
                      icon: Icons.school_outlined,
                      message: 'No concepts yet. Add one from inside a study space, then come back here to practice.',
                    ),
                  ],
                );
              }

              return ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 8, 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Learn', style: theme.textTheme.headlineLarge),
                              const SizedBox(height: 4),
                              Text(
                                '$dueCount flashcard${dueCount == 1 ? '' : 's'} due · ${mastery.length} concept${mastery.length == 1 ? '' : 's'}',
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        ProfileIconButton(authService: widget.authService),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: _ModeButton(icon: Icons.style_rounded, label: 'Flashcards', color: StudyOsColors.amber, onTap: _openFlashcardReview),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ModeButton(icon: Icons.track_changes_rounded, label: 'Quiz', color: StudyOsColors.primary, onTap: () => _pickConceptThen(true)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ModeButton(icon: Icons.edit_note_rounded, label: 'Practice', color: theme.colorScheme.onSurfaceVariant, onTap: () => _pickConceptThen(false)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        for (final s in subjects) ...[
                          ChoiceChip(label: Text(s), selected: _filter == s, onSelected: (_) => setState(() => _filter = s)),
                          const SizedBox(width: 6),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        for (final item in filtered)
                          Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _openConcept(item),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    MasteryRing(mastery: (item['mastery'] as num).toDouble()),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(item['concept_name'] as String, style: theme.textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                                          if (item['knowledge_space_slug'] != null)
                                            Text(
                                              _spaceNames[item['knowledge_space_slug']] ?? item['knowledge_space_slug'] as String,
                                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.icon, required this.label, required this.color, required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: color.withValues(alpha: theme.brightness == Brightness.dark ? 0.16 : 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(label, style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
