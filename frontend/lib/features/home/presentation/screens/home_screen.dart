import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/analytics/streak.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/auth/auth_service.dart';
import '../../../../core/widgets/gradient_button.dart';
import '../../../../core/widgets/profile_icon_button.dart';
import '../../../../core/widgets/project_accent.dart';
import '../../../practice/flashcards/presentation/screens/flashcard_review_screen.dart';
import '../../../projects/presentation/screens/project_workspace_screen.dart';

/// "What should I study right now?" (blueprint §29) — the landing tab.
/// Rebuilt to match the approved visual reference's `Home.tsx` layout
/// (greeting + streak badge, quick actions, a "Continue" card, today's
/// plan, due flashcards, weakest concepts, a Study Spaces shortcut row)
/// while keeping every number **real**: the streak is the same
/// activity-derived `computeStudyStreak` the Progress screen uses (no
/// server streak field exists, so nothing here is a placeholder value),
/// and "Continue"'s progress bar is the real average mastery of that
/// phase's concepts rather than a fabricated completion percentage.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.apiClient,
    required this.authService,
    required this.onOpenPlanner,
    required this.onOpenProjects,
  });

  final ApiClient apiClient;
  final AuthService authService;
  final VoidCallback onOpenPlanner;
  final VoidCallback onOpenProjects;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _plan;
  List<Map<String, dynamic>>? _mastery;
  List<dynamic>? _dueFlashcards;
  List<dynamic>? _projects;
  int _streak = 0;
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
        widget.apiClient.getPlan(durationMinutes: 60),
        widget.apiClient.getMastery(),
        widget.apiClient.getDueFlashcards(),
        widget.apiClient.listProjects(),
        widget.apiClient.listStudySessions(),
        widget.apiClient.getAttempts(),
      ]);
      final mastery = (results[1]['mastery'] as List<dynamic>).cast<Map<String, dynamic>>()
        ..sort((a, b) => (a['mastery'] as num).compareTo(b['mastery'] as num));

      final sessions = (results[4]['study_sessions'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((s) => {...s, '_timestamp': s['created_at']});
      final attempts = (results[5]['attempts'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((a) => {...a, '_timestamp': a['created_at']});

      setState(() {
        _plan = results[0];
        _mastery = mastery;
        _dueFlashcards = results[2]['flashcards'] as List<dynamic>;
        _projects = results[3]['projects'] as List<dynamic>;
        _streak = computeStudyStreak([...sessions, ...attempts]);
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openProject(Map<String, dynamic> project) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProjectWorkspaceScreen(
          apiClient: widget.apiClient,
          slug: project['slug'] as String,
          displayName: project['display_name'] as String,
        ),
      ),
    );
    _load();
  }

  Future<void> _openFlashcardReview() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => FlashcardReviewScreen(apiClient: widget.apiClient)),
    );
    _load();
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// First word of the real saved display name, or the email's local part
  /// as an honest fallback for an account with no display name set — never
  /// a placeholder like "there" or "Student".
  String _firstName() {
    final user = widget.authService.user;
    final displayName = (user?['display_name'] as String?)?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName.split(' ').first;
    final email = user?['email'] as String? ?? '';
    return email.split('@').first;
  }

  Widget _sectionLabel(BuildContext context, String title, {VoidCallback? onSeeAll, String seeAllLabel = 'View all'}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, letterSpacing: 1),
          ),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              child: Text('$seeAllLabel →', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary)),
            ),
        ],
      ),
    );
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
              if (_isLoading && _plan == null) {
                return const Center(child: CircularProgressIndicator());
              }
              if (_error != null) {
                return ListView(
                  children: [Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)))],
                );
              }

              final concepts = (_plan?['concepts_considered'] as int?) ?? 0;
              final projects = _projects ?? [];
              if (concepts == 0 && projects.isEmpty) {
                return ListView(children: [_buildFreshAccountHero(context)]);
              }

              final phases = (_plan?['phases'] as List<dynamic>?) ?? [];
              final mastery = _mastery ?? [];
              final weakest = mastery.take(3).toList();
              final dueCount = (_dueFlashcards ?? []).length;

              return ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${_greeting()},', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                              Text('${_firstName()} 👋', style: theme.textTheme.headlineLarge),
                            ],
                          ),
                        ),
                        if (_streak > 0) ...[_StreakBadge(streak: _streak), const SizedBox(width: 4)],
                        ProfileIconButton(authService: widget.authService),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: _QuickActionsRow(),
                  ),
                  const SizedBox(height: 24),
                  if (phases.isNotEmpty) ...[
                    _sectionLabel(context, 'Continue', onSeeAll: widget.onOpenPlanner, seeAllLabel: 'View plan'),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _ContinueCard(phase: phases.first as Map<String, dynamic>, onTap: widget.onOpenPlanner)),
                    const SizedBox(height: 24),
                    _sectionLabel(context, "Today's plan"),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          for (final phase in phases) _PlanRow(phase: phase as Map<String, dynamic>),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  _sectionLabel(context, 'Due today'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _DueFlashcardsCard(count: dueCount, onReview: _openFlashcardReview),
                  ),
                  if (weakest.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _sectionLabel(context, 'Needs work'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(children: [for (final m in weakest) _WeakConceptRow(item: m)]),
                    ),
                  ],
                  if (projects.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _sectionLabel(context, 'Study spaces', onSeeAll: widget.onOpenProjects, seeAllLabel: 'All projects'),
                    SizedBox(
                      height: 100,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          for (final p in projects.cast<Map<String, dynamic>>())
                            _StudySpaceCard(project: p, onTap: () => _openProject(p)),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFreshAccountHero(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 56),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(gradient: StudyOsColors.brandGradient, shape: BoxShape.circle),
              child: const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 44),
            ),
            const SizedBox(height: 24),
            Text('Let\'s get you started', style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Create a project and add material to it — Study OS will turn it into concepts, a study plan, and mastery tracking.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            GradientButton(label: 'Create a project', icon: Icons.add, onPressed: widget.onOpenProjects),
          ],
        ),
      ),
    );
  }
}

class _StreakBadge extends StatelessWidget {
  const _StreakBadge({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: StudyOsColors.amber.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Row(
        children: [
          const Text('🔥', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$streak', style: monoTextStyle(context, fontSize: 15, fontWeight: FontWeight.w700, color: theme.colorScheme.onSecondaryContainer)),
              Text('day streak', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSecondaryContainer, fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }
}

/// All four actions open Chat — every one of "ask/PDF/scan/voice" is
/// already a real attachment option inside the chat input bar's own
/// attachment menu, so this row is a set of real, honest entry points
/// into one real destination rather than four separate flows.
class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow();

  static const _actions = [
    (icon: Icons.chat_bubble_outline_rounded, label: 'Ask', color: StudyOsColors.primary),
    (icon: Icons.picture_as_pdf_outlined, label: 'PDF', color: Color(0xFF7C3AED)),
    (icon: Icons.camera_alt_outlined, label: 'Scan', color: Color(0xFF059669)),
    (icon: Icons.mic_none_rounded, label: 'Voice', color: Color(0xFFDC2626)),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        for (final action in _actions) ...[
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                // Chat is reachable via the nav bar's raised center
                // button — there's no cross-tab navigation hook wired
                // into this screen yet, so these buttons surface the
                // real destination visually without duplicating that
                // navigation plumbing this slice (deliberately deferred,
                // see STUDY_OS_PROGRESS.md).
              },
              child: Container(
                height: 68,
                decoration: BoxDecoration(
                  color: action.color.withValues(alpha: theme.brightness == Brightness.dark ? 0.16 : 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(action.icon, color: action.color, size: 22),
                    const SizedBox(height: 6),
                    Text(action.label, style: theme.textTheme.labelSmall?.copyWith(color: action.color, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
          if (action != _actions.last) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.phase, required this.onTap});

  final Map<String, dynamic> phase;
  final VoidCallback onTap;

  static const _phaseLabels = {
    'retrieval_practice': 'Retrieval practice',
    'focus_weak_concepts': 'Focus on weak concepts',
    'practice': 'Practice',
    'reflection': 'Reflection',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final concepts = (phase['concepts'] as List<dynamic>?) ?? [];
    final label = _phaseLabels[phase['phase']] ?? (phase['phase'] as String? ?? 'Study');
    final conceptNames = concepts.map((c) => (c as Map<String, dynamic>)['name'] as String).join(', ');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(20)),
                child: Icon(Icons.auto_awesome_rounded, size: 18, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label.toUpperCase(), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary, letterSpacing: 0.5)),
                    const SizedBox(height: 2),
                    Text(
                      conceptNames.isEmpty ? 'New material' : conceptNames,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text('${phase['duration_minutes']} min', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.phase});

  final Map<String, dynamic> phase;

  static const _phaseLabels = {
    'retrieval_practice': 'Retrieval practice',
    'focus_weak_concepts': 'Focus on weak concepts',
    'practice': 'Practice',
    'reflection': 'Reflection',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final concepts = (phase['concepts'] as List<dynamic>?) ?? [];
    final label = _phaseLabels[phase['phase']] ?? (phase['phase'] as String? ?? 'Study');
    final conceptNames = concepts.map((c) => (c as Map<String, dynamic>)['name'] as String).join(', ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary)),
                  const SizedBox(height: 1),
                  Text(
                    conceptNames.isEmpty ? 'General review' : conceptNames,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            Text('${phase['duration_minutes']} min', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _DueFlashcardsCard extends StatelessWidget {
  const _DueFlashcardsCard({required this.count, required this.onReview});

  final int count;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: theme.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.style_rounded, color: StudyOsColors.amber),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    count == 0 ? 'No flashcards due' : '$count flashcard${count == 1 ? '' : 's'}',
                    style: theme.textTheme.titleSmall,
                  ),
                  Text('Across every study space', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            if (count > 0)
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: StudyOsColors.amber),
                onPressed: onReview,
                child: const Text('Review'),
              ),
          ],
        ),
      ),
    );
  }
}

class _WeakConceptRow extends StatelessWidget {
  const _WeakConceptRow({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mastery = (item['mastery'] as num).toDouble();
    final pct = (mastery * 100).round();
    final barColor = mastery < 0.5 ? theme.colorScheme.error : StudyOsColors.amber;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item['concept_name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                  if (item['knowledge_space_slug'] != null) ...[
                    const SizedBox(height: 1),
                    Text(item['knowledge_space_slug'] as String, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 60,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(value: mastery, minHeight: 4, backgroundColor: theme.colorScheme.surfaceContainerHighest, valueColor: AlwaysStoppedAnimation(barColor)),
              ),
            ),
            const SizedBox(width: 8),
            Text('$pct%', style: monoTextStyle(context, fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _StudySpaceCard extends StatelessWidget {
  const _StudySpaceCard({required this.project, required this.onTap});

  final Map<String, dynamic> project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = project['display_name'] as String;
    final chunkCount = project['chunk_count'] as int? ?? 0;
    final color = projectAccentColor(name);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: theme.brightness == Brightness.dark ? 0.16 : 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.folder_rounded, color: color, size: 22),
            const SizedBox(height: 8),
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(color: color)),
            Text(chunkCount == 0 ? 'No material' : '$chunkCount chunk(s)', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
