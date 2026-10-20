import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/analytics/streak.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/auth/auth_service.dart';
import '../../../../core/widgets/gradient_button.dart';
import '../../../../core/widgets/mastery_ring.dart';
import '../../../../core/widgets/profile_icon_button.dart';
import '../../../../core/widgets/project_accent.dart';
import '../../../../core/widgets/sage_mascot.dart';
import '../../../chat/chat_quick_action.dart';
import '../../../practice/flashcards/presentation/screens/flashcard_review_screen.dart';
import '../../../projects/presentation/screens/project_workspace_screen.dart';

/// "What should I study right now?" — the landing tab.
///
/// v3 (2026-10-19), rebuilt after the user called v2 "dull", "generic" and
/// "not inviting": a Duolingo-style stats bar (streak, cards due), a daily
/// goal hero with Sage the mascot, a big "Continue" card with one obvious
/// Start button, colourful subject tiles with mastery bars (Khan
/// Academy's course grid), a Quizlet-style flashcard deck card, and the
/// chat tools as round buttons.
///
/// Every number is still real: the streak is the activity-derived
/// `computeStudyStreak` the Progress screen uses; "today" counts the
/// student's own question attempts since local midnight; a subject's bar
/// is the average mastery of its practised concepts; due cards come from
/// the server (capped at the request's limit, shown as "20+").
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.apiClient,
    required this.authService,
    required this.onOpenPlanner,
    required this.onOpenProjects,
    required this.onOpenPractice,
    required this.onQuickAction,
    this.profileButtonKey,
  });

  final ApiClient apiClient;
  final AuthService authService;
  final VoidCallback onOpenPlanner;
  final VoidCallback onOpenProjects;
  final VoidCallback onOpenPractice;

  /// Ask/PDF/Scan/Voice all switch to the Chat tab and immediately run the
  /// matching action there — see `chat_quick_action.dart`.
  final void Function(ChatQuickAction) onQuickAction;

  /// Lets the first-run tour spotlight the profile button (app_tour.dart).
  final GlobalKey? profileButtonKey;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// Questions answered today that count as "goal met". A fixed, stated
/// target — there's no per-user goal setting yet.
const _dailyGoal = 10;
const _dueLimit = 20;

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _plan;
  List<Map<String, dynamic>>? _mastery;
  List<dynamic>? _dueFlashcards;
  List<dynamic>? _projects;
  int _streak = 0;
  int _answeredToday = 0;
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
        widget.apiClient.getDueFlashcards(limit: _dueLimit),
        widget.apiClient.listProjects(),
        widget.apiClient.listStudySessions(),
        widget.apiClient.getAttempts(),
      ]);
      final mastery = (results[1]['mastery'] as List<dynamic>).cast<Map<String, dynamic>>()
        ..sort((a, b) => (a['mastery'] as num).compareTo(b['mastery'] as num));

      final sessions = (results[4]['study_sessions'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((s) => {...s, '_timestamp': s['created_at']});
      final attempts = (results[5]['attempts'] as List<dynamic>).cast<Map<String, dynamic>>();
      final now = DateTime.now();
      final answeredToday = attempts.where((a) {
        final at = DateTime.tryParse(a['created_at'] as String? ?? '')?.toLocal();
        return at != null && at.year == now.year && at.month == now.month && at.day == now.day;
      }).length;

      setState(() {
        _plan = results[0];
        _mastery = mastery;
        _dueFlashcards = results[2]['flashcards'] as List<dynamic>;
        _projects = results[3]['projects'] as List<dynamic>;
        _streak = computeStudyStreak([...sessions, ...attempts.map((a) => {...a, '_timestamp': a['created_at']})]);
        _answeredToday = answeredToday;
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
  /// as an honest fallback for an account with no display name set.
  String _firstName() {
    final user = widget.authService.user;
    final displayName = (user?['display_name'] as String?)?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName.split(' ').first;
    final email = user?['email'] as String? ?? '';
    return email.split('@').first;
  }

  /// Average mastery per subject slug, over the concepts practised there.
  Map<String, double> _subjectMastery() {
    final sums = <String, (double, int)>{};
    for (final m in _mastery ?? const <Map<String, dynamic>>[]) {
      final slug = m['knowledge_space_slug'] as String?;
      if (slug == null) continue;
      final (sum, n) = sums[slug] ?? (0.0, 0);
      sums[slug] = (sum + (m['mastery'] as num).toDouble(), n + 1);
    }
    return {for (final e in sums.entries) e.key: e.value.$1 / e.value.$2};
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
                return const Center(child: SageMascot(size: 88, mood: SageMood.thinking));
              }
              if (_error != null) {
                return ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const SizedBox(height: 40),
                    const Center(child: SageMascot(size: 96, mood: SageMood.thinking)),
                    const SizedBox(height: 16),
                    Text("Couldn't load your dashboard", style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
                    const SizedBox(height: 6),
                    Text(_error!, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    GradientButton(label: 'Try again', icon: Icons.refresh_rounded, onPressed: _load),
                  ],
                );
              }

              final concepts = (_plan?['concepts_considered'] as int?) ?? 0;
              final projects = (_projects ?? []).cast<Map<String, dynamic>>();
              if (concepts == 0 && projects.isEmpty) {
                return ListView(children: [_header(context), _buildFreshAccountHero(context)]);
              }

              final phases = (_plan?['phases'] as List<dynamic>?) ?? [];
              final weakest = (_mastery ?? []).where((m) => (m['mastery'] as num) < 0.75).take(4).toList();
              final dueCount = (_dueFlashcards ?? []).length;
              final subjectMastery = _subjectMastery();

              return ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  _header(context),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _DailyGoalCard(answered: _answeredToday, goal: _dailyGoal, name: _firstName(), onPractice: widget.onOpenPractice),
                  ),
                  if (phases.isNotEmpty) ...[
                    const _SectionTitle('Continue learning'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _ContinueCard(phase: phases.first as Map<String, dynamic>, totalPhases: phases.length, onStart: widget.onOpenPlanner),
                    ),
                  ],
                  _SectionTitle('Your subjects', actionLabel: 'See all', onAction: widget.onOpenProjects),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _SubjectGrid(
                      projects: projects,
                      mastery: subjectMastery,
                      onOpen: _openProject,
                      onAdd: widget.onOpenProjects,
                    ),
                  ),
                  const _SectionTitle('Flashcards'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _FlashcardDeckCard(count: dueCount, capped: dueCount >= _dueLimit, onReview: _openFlashcardReview),
                  ),
                  const _SectionTitle('Study tools'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _ToolsRow(onAction: widget.onQuickAction),
                  ),
                  if (weakest.isNotEmpty) ...[
                    _SectionTitle('Needs a little love', actionLabel: 'Practice', onAction: widget.onOpenPractice),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(children: [for (final m in weakest) _WeakConceptRow(item: m)]),
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

  /// Greeting on the left; the Duolingo-style stat chips and profile on the right.
  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    final due = (_dueFlashcards ?? []).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_greeting(), style: theme.textTheme.labelMedium),
                Text(_firstName(), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.headlineLarge),
              ],
            ),
          ),
          _StatChip(
            icon: Icons.local_fire_department_rounded,
            color: _streak > 0 ? StudyOsColors.streak : theme.colorScheme.onSurfaceVariant,
            value: '$_streak',
            tooltip: '$_streak-day study streak',
          ),
          const SizedBox(width: 6),
          _StatChip(
            icon: Icons.style_rounded,
            color: due > 0 ? StudyOsColors.xp : theme.colorScheme.onSurfaceVariant,
            value: due >= _dueLimit ? '$_dueLimit+' : '$due',
            tooltip: 'Flashcards due',
          ),
          KeyedSubtree(key: widget.profileButtonKey, child: ProfileIconButton(authService: widget.authService)),
        ],
      ),
    );
  }

  Widget _buildFreshAccountHero(BuildContext context) {
    final theme = Theme.of(context);
    const steps = [
      (icon: Icons.create_new_folder_rounded, color: StudyOsColors.primary, title: 'Create a subject', body: 'One for each course or topic you\'re studying.'),
      (icon: Icons.upload_file_rounded, color: StudyOsColors.xp, title: 'Add your notes', body: 'PDFs, pasted text or web links — Study OS reads them for you.'),
      (icon: Icons.emoji_events_rounded, color: StudyOsColors.success, title: 'Practise and grow', body: 'Flashcards, quizzes and a study plan built from your material.'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            decoration: BoxDecoration(gradient: StudyOsColors.heroGradient, borderRadius: BorderRadius.circular(28)),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hi ${_firstName()}!', style: theme.textTheme.headlineMedium?.copyWith(color: Colors.white)),
                      const SizedBox(height: 6),
                      Text(
                        "I'm Sage, your study buddy. Let's set up your first subject.",
                        style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.92)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const SageMascot(size: 92, mood: SageMood.cheer),
              ],
            ),
          ),
          const SizedBox(height: 20),
          for (final (i, step) in steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CardSurface(
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: step.color, borderRadius: BorderRadius.circular(14)),
                      child: Icon(step.icon, color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${i + 1}. ${step.title}', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(step.body, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          GradientButton(label: 'Create my first subject', icon: Icons.add_rounded, onPressed: widget.onOpenProjects),
          const SizedBox(height: 28),
          Align(alignment: Alignment.centerLeft, child: Text('Or just ask me something', style: theme.textTheme.titleLarge)),
          const SizedBox(height: 12),
          _ToolsRow(onAction: widget.onQuickAction),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// building blocks

/// A white (dark: navy) card with the v3 border and a chunky bottom edge.
class _CardSurface extends StatelessWidget {
  const _CardSurface({required this.child, this.onTap, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(20);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: radius,
        border: Border.all(color: theme.colorScheme.outline, width: 1.5),
        boxShadow: [BoxShadow(color: theme.colorScheme.outline, offset: const Offset(0, 3))],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(borderRadius: radius, onTap: onTap, child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 12, 10),
      child: Row(
        children: [
          Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
          if (onAction != null) TextButton(onPressed: onAction, child: Text(actionLabel ?? 'See all')),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.color, required this.value, required this.tooltip});

  final IconData icon;
  final Color color;
  final String value;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 3),
            Text(value, style: monoTextStyle(context, fontSize: 15, fontWeight: FontWeight.w900, color: color)),
          ],
        ),
      ),
    );
  }
}

class _DailyGoalCard extends StatelessWidget {
  const _DailyGoalCard({required this.answered, required this.goal, required this.name, required this.onPractice});

  final int answered;
  final int goal;
  final String name;
  final VoidCallback onPractice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = answered >= goal;
    final progress = (answered / goal).clamp(0.0, 1.0);
    final headline = done
        ? 'Goal smashed, $name!'
        : answered == 0
            ? 'Ready for today?'
            : '${goal - answered} more to hit your goal';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
      decoration: BoxDecoration(
        gradient: done ? const LinearGradient(colors: [Color(0xFF22C55E), Color(0xFF0EA5A4)]) : StudyOsColors.heroGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: (done ? StudyOsColors.success : StudyOsColors.primary).withValues(alpha: 0.30), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DAILY GOAL', style: theme.textTheme.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.85), letterSpacing: 1.2)),
                const SizedBox(height: 4),
                Text(headline, style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white)),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 12,
                    backgroundColor: Colors.white.withValues(alpha: 0.25),
                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$answered / $goal questions today',
                  style: monoTextStyle(context, fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const SizedBox(height: 12),
                _WhitePillButton(label: done ? 'Keep practising' : 'Practise now', onTap: onPractice),
              ],
            ),
          ),
          const SizedBox(width: 6),
          SageMascot(size: 92, mood: done ? SageMood.cheer : SageMood.happy),
        ],
      ),
    );
  }
}

/// A white pill on a coloured card — the hero's secondary-weight action.
class _WhitePillButton extends StatelessWidget {
  const _WhitePillButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(fontFamily: displayFontFamily, fontSize: 14, fontWeight: FontWeight.w900, color: StudyOsColors.primaryDark)),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_forward_rounded, size: 18, color: StudyOsColors.primaryDark),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.phase, required this.totalPhases, required this.onStart});

  final Map<String, dynamic> phase;
  final int totalPhases;
  final VoidCallback onStart;

  static const _phases = {
    'retrieval_practice': (label: 'Retrieval practice', icon: Icons.psychology_rounded, color: StudyOsColors.xp),
    'focus_weak_concepts': (label: 'Strengthen weak spots', icon: Icons.fitness_center_rounded, color: StudyOsColors.streak),
    'practice': (label: 'Practice', icon: Icons.edit_note_rounded, color: StudyOsColors.primary),
    'reflection': (label: 'Reflection', icon: Icons.self_improvement_rounded, color: Color(0xFF0EA5A4)),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final concepts = (phase['concepts'] as List<dynamic>?) ?? [];
    final info = _phases[phase['phase']] ?? (label: phase['phase'] as String? ?? 'Study', icon: Icons.auto_awesome_rounded, color: StudyOsColors.primary);
    final conceptNames = concepts.map((c) => (c as Map<String, dynamic>)['name'] as String).join(' · ');

    return _CardSurface(
      onTap: onStart,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: info.color, borderRadius: BorderRadius.circular(16)),
                child: Icon(info.icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(info.label, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      conceptNames.isEmpty ? 'New material' : conceptNames,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _InfoPill(icon: Icons.schedule_rounded, text: '${phase['duration_minutes']} min'),
              const SizedBox(width: 8),
              _InfoPill(icon: Icons.flag_rounded, text: 'Step 1 of $totalPhases'),
              const Spacer(),
              GradientButton(label: 'Start', expand: false, color: StudyOsColors.success, onPressed: onStart),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(text, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _SubjectGrid extends StatelessWidget {
  const _SubjectGrid({required this.projects, required this.mastery, required this.onOpen, required this.onAdd});

  final List<Map<String, dynamic>> projects;
  final Map<String, double> mastery;
  final void Function(Map<String, dynamic>) onOpen;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      for (final p in projects.take(5)) _SubjectTile(project: p, mastery: mastery[p['slug']], onTap: () => onOpen(p)),
      _AddSubjectTile(onTap: onAdd),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [for (final t in tiles) SizedBox(width: width, height: 150, child: t)],
        );
      },
    );
  }
}

class _SubjectTile extends StatelessWidget {
  const _SubjectTile({required this.project, required this.mastery, required this.onTap});

  final Map<String, dynamic> project;
  final double? mastery;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = project['display_name'] as String;
    final chunks = project['chunk_count'] as int? ?? 0;
    final color = projectAccentColor(name);
    final radius = BorderRadius.circular(22);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: radius,
        boxShadow: [BoxShadow(color: StudyOsColors.ledgeOf(color), offset: const Offset(0, 4))],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Stack(
            children: [
              // a big faint icon in the corner, for texture
              Positioned(
                right: -14,
                bottom: -14,
                child: Icon(subjectIcon(name), size: 92, color: Colors.white.withValues(alpha: 0.16)),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(12)),
                      child: Icon(subjectIcon(name), color: Colors.white, size: 22),
                    ),
                    const Spacer(),
                    Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, height: 1.15)),
                    const SizedBox(height: 6),
                    if (mastery != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: mastery,
                          minHeight: 6,
                          backgroundColor: Colors.white.withValues(alpha: 0.28),
                          valueColor: const AlwaysStoppedAnimation(Colors.white),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('${(mastery! * 100).round()}% mastered', style: theme.textTheme.labelSmall?.copyWith(color: Colors.white)),
                    ] else
                      Text(
                        chunks == 0 ? 'No notes yet' : 'Ready to practise',
                        style: theme.textTheme.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddSubjectTile extends StatelessWidget {
  const _AddSubjectTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(22);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(borderRadius: radius, border: Border.all(color: theme.colorScheme.outline, width: 2)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, shape: BoxShape.circle),
                child: Icon(Icons.add_rounded, color: theme.colorScheme.primary, size: 26),
              ),
              const SizedBox(height: 8),
              Text('New subject', style: theme.textTheme.titleSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlashcardDeckCard extends StatelessWidget {
  const _FlashcardDeckCard({required this.count, required this.capped, required this.onReview});

  final int count;
  final bool capped;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allDone = count == 0;
    return _CardSurface(
      child: Row(
        children: [
          // a little stacked deck
          SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              children: [
                Positioned(left: 10, top: 0, child: _deckCard(StudyOsColors.xp.withValues(alpha: 0.35), -0.12)),
                Positioned(left: 4, top: 4, child: _deckCard(StudyOsColors.xp.withValues(alpha: 0.6), -0.05)),
                Positioned(
                  left: 0,
                  top: 8,
                  child: _deckCard(
                    StudyOsColors.xp,
                    0.04,
                    child: Center(
                      child: allDone
                          ? const Icon(Icons.check_rounded, color: Colors.white, size: 26)
                          : Text(capped ? '$count+' : '$count', style: monoTextStyle(context, fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(allDone ? 'All caught up!' : '${capped ? '$count+' : count} card${count == 1 ? '' : 's'} to review', style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  allDone ? 'New cards show up here when due.' : 'Review now, remember for good.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (!allDone) ...[
            const SizedBox(width: 8),
            GradientButton(label: 'Review', expand: false, color: StudyOsColors.xp, onPressed: onReview),
          ],
        ],
      ),
    );
  }

  Widget _deckCard(Color color, double angle, {Widget? child}) {
    return Transform.rotate(
      angle: angle,
      child: Container(width: 46, height: 54, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)), child: child),
    );
  }
}

class _ToolsRow extends StatelessWidget {
  const _ToolsRow({required this.onAction});

  final void Function(ChatQuickAction) onAction;

  static const _tools = [
    (action: ChatQuickAction.ask, icon: Icons.forum_rounded, label: 'Ask Sage', color: StudyOsColors.primary),
    (action: ChatQuickAction.scan, icon: Icons.photo_camera_rounded, label: 'Scan', color: Color(0xFF0EA5A4)),
    (action: ChatQuickAction.pdf, icon: Icons.picture_as_pdf_rounded, label: 'PDF', color: Color(0xFFE2457A)),
    (action: ChatQuickAction.voice, icon: Icons.mic_rounded, label: 'Voice', color: StudyOsColors.streak),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final tool in _tools)
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onAction(tool.action),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: tool.color,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: StudyOsColors.ledgeOf(tool.color), offset: const Offset(0, 3))],
                      ),
                      child: Icon(tool.icon, color: Colors.white, size: 27),
                    ),
                    const SizedBox(height: 8),
                    Text(tool.label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurface)),
                  ],
                ),
              ),
            ),
          ),
      ],
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
    final slug = item['knowledge_space_slug'] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _CardSurface(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            MasteryRing(mastery: mastery, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item['concept_name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                  if (slug != null) Text(slug.replaceAll('-', ' '), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
