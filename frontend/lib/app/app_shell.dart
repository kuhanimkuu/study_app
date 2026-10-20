import 'package:flutter/material.dart';

import '../core/auth/auth_service.dart';
import '../features/chat/chat_quick_action.dart';
import '../features/chat/presentation/screens/chat_screen.dart';
import '../features/home/presentation/screens/home_screen.dart';
import '../features/learning/concepts/presentation/screens/learn_hub_screen.dart';
import '../features/planner/presentation/screens/planner_screen.dart';
import '../features/projects/presentation/screens/projects_list_screen.dart';
import '../core/widgets/sage_mascot.dart';
import 'app_tour.dart';
import 'theme.dart';

/// Shown once the user is authenticated — bottom nav switching between the
/// top-level screens. AuthGate decides whether this or the login/signup
/// flow is on screen; this widget doesn't know about that decision.
///
/// Nav shape takes the approved visual reference
/// (`kuhanimkuu/DesignStudyOSMobileApp`'s `BottomNav.tsx`) as a starting
/// point, not a literal copy: its raised, gradient-filled circular Chat
/// button is kept as the signature "twist", but the destinations either
/// side of it are this project's own call, made twice now based on real
/// use (2026-09-19):
/// - **Projects ("Study Spaces") is a real tab**, unlike the reference —
///   every other feature (Concepts, Flashcards, Notes, per-project Chat,
///   Search) lives inside a Project, so demoting it to a shortcut made it
///   too hard to find.
/// - **Profile is NOT a tab** — it's reached via a persistent
///   `ProfileIconButton` in the top-right corner of every top-level
///   screen instead (see that widget), the same place a settings/account
///   icon conventionally lives, freeing a nav slot back up.
/// That nets back out to 4 flat destinations (Home/Projects/Learn/
/// Planner), which keeps the Chat FAB's centering simple again — see
/// `_StudyOsBottomNav`'s doc comment.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.authService});

  final AuthService authService;

  @override
  State<AppShell> createState() => _AppShellState();
}

enum _Tab { home, projects, learn, chat, planner }

class _AppShellState extends State<AppShell> {
  _Tab _tab = _Tab.home;

  /// One-shot signal from Home's quick-actions row to the (already
  /// mounted, persistent-in-the-IndexedStack) Chat tab — see
  /// `ChatQuickAction`'s doc comment for why a `ValueNotifier` rather than
  /// a constructor param.
  final _chatQuickAction = ValueNotifier<ChatQuickAction?>(null);

  // Spotlight targets for the first-run tour (see app_tour.dart).
  final _tabKeys = {for (final t in _Tab.values) t: GlobalKey()};
  final _profileKey = GlobalKey();
  bool _showTour = false;

  @override
  void initState() {
    super.initState();
    AppTour.replayRequested.addListener(_onReplayRequested);
    AppTour.shouldShow().then((show) {
      if (show && mounted) setState(() => _showTour = true);
    });
  }

  void _onReplayRequested() {
    if (!AppTour.replayRequested.value || !mounted) return;
    AppTour.replayRequested.value = false;
    setState(() {
      _tab = _Tab.home; // the profile step points at Home's profile button
      _showTour = true;
    });
  }

  void _finishTour() {
    AppTour.markSeen();
    setState(() => _showTour = false);
  }

  List<AppTourStep> _tourSteps() => [
        const AppTourStep(
          title: 'Welcome to Study OS!',
          body: "I'm Sage, your study buddy. Let me show you around — it only takes a minute.",
          color: StudyOsColors.primary,
          icon: Icons.waving_hand_rounded,
          mood: SageMood.cheer,
        ),
        AppTourStep(
          target: _tabKeys[_Tab.home],
          title: 'Home',
          body: 'Your daily goal, streak and cards due — plus what to study next. Start here every day.',
          color: StudyOsColors.primary,
          icon: Icons.home_rounded,
        ),
        AppTourStep(
          target: _tabKeys[_Tab.projects],
          title: 'Subjects',
          body: 'Make one for each course. Add PDFs, notes or web links and I turn them into concepts, flashcards and quizzes.',
          color: StudyOsColors.success,
          icon: Icons.auto_stories_rounded,
        ),
        AppTourStep(
          target: _tabKeys[_Tab.chat],
          title: 'Chat with me',
          body: 'Ask anything, or send me a photo, PDF, voice note or link. I answer using your own AI key — add it in Profile.',
          color: StudyOsColors.primary,
          icon: Icons.forum_rounded,
        ),
        AppTourStep(
          target: _tabKeys[_Tab.learn],
          title: 'Practice',
          body: 'Flashcards, quizzes and practice questions on everything in your subjects. Your mastery grows as you go.',
          color: StudyOsColors.xp,
          icon: Icons.bolt_rounded,
        ),
        AppTourStep(
          target: _tabKeys[_Tab.planner],
          title: 'Plan',
          body: 'Set goals with target dates, and get a study plan and sessions built around what you need most.',
          color: StudyOsColors.streak,
          icon: Icons.calendar_month_rounded,
        ),
        AppTourStep(
          target: _profileKey,
          title: 'Profile',
          body: 'Your AI key, settings, progress and saved chat files live here. You can replay this tour from here too.',
          color: StudyOsColors.primary,
          icon: Icons.person_rounded,
          mood: SageMood.cheer,
        ),
      ];

  void _select(_Tab tab) => setState(() => _tab = tab);

  void _runChatQuickAction(ChatQuickAction action) {
    _chatQuickAction.value = action;
    _select(_Tab.chat);
  }

  @override
  void dispose() {
    AppTour.replayRequested.removeListener(_onReplayRequested);
    _chatQuickAction.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = <_Tab, Widget>{
      _Tab.home: HomeScreen(
        apiClient: widget.authService.apiClient,
        authService: widget.authService,
        onOpenPlanner: () => _select(_Tab.planner),
        onOpenProjects: () => _select(_Tab.projects),
        onOpenPractice: () => _select(_Tab.learn),
        onQuickAction: _runChatQuickAction,
        profileButtonKey: _profileKey,
      ),
      _Tab.projects: ProjectsListScreen(apiClient: widget.authService.apiClient, authService: widget.authService),
      _Tab.learn: LearnHubScreen(apiClient: widget.authService.apiClient, authService: widget.authService),
      _Tab.chat: ChatScreen(authService: widget.authService, pendingAction: _chatQuickAction),
      _Tab.planner: PlannerScreen(apiClient: widget.authService.apiClient, authService: widget.authService),
    };

    final shell = Scaffold(
      body: IndexedStack(
        index: _Tab.values.indexOf(_tab),
        children: [for (final t in _Tab.values) screens[t]!],
      ),
      bottomNavigationBar: _StudyOsBottomNav(active: _tab, onSelect: _select, keys: _tabKeys),
    );
    if (!_showTour) return shell;
    return Stack(
      children: [
        shell,
        Positioned.fill(child: AppTourOverlay(steps: _tourSteps(), onDone: _finishTour)),
      ],
    );
  }
}

/// A raised gradient circle for Chat floats above the bar — the
/// reference's signature "twist". With exactly 4 flat destinations either
/// side split 2-and-2, the reserved gap for the FAB lands at true
/// screen-center on any width — still computed via `LayoutBuilder` rather
/// than a hardcoded pixel gap (kept from the 5-tab version this replaced,
/// since it's no more code and stays correct if a tab is ever added back).
class _StudyOsBottomNav extends StatelessWidget {
  const _StudyOsBottomNav({required this.active, required this.onSelect, required this.keys});

  final _Tab active;
  final void Function(_Tab) onSelect;

  /// Spotlight targets for the first-run tour, one per tab.
  final Map<_Tab, GlobalKey> keys;

  // Labels say what each tab is FOR (2026-10-19, design v3 — the user
  // found things "hard to find"): a project is the student's *subject*
  // (its notes, concepts, cards, chat), and the Learn hub is where they
  // *practise*. Internal names (_Tab.projects/_Tab.learn) are unchanged.
  static const _leftItems = [
    (tab: _Tab.home, label: 'Home', icon: Icons.home_outlined, iconFilled: Icons.home_rounded, color: StudyOsColors.primary),
    (tab: _Tab.projects, label: 'Subjects', icon: Icons.auto_stories_outlined, iconFilled: Icons.auto_stories_rounded, color: StudyOsColors.success),
  ];
  static const _rightItems = [
    (tab: _Tab.learn, label: 'Practice', icon: Icons.bolt_outlined, iconFilled: Icons.bolt_rounded, color: StudyOsColors.xp),
    (tab: _Tab.planner, label: 'Plan', icon: Icons.calendar_month_outlined, iconFilled: Icons.calendar_month_rounded, color: StudyOsColors.streak),
  ];
  static const _totalSlots = 5; // 2 left items + 1 gap slot (for the FAB) + 2 right items
  static const _fabSize = 62.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(top: BorderSide(color: theme.colorScheme.outline, width: 1.5)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final slotWidth = constraints.maxWidth / _totalSlots;
            final fabCenterX = (_leftItems.length + 0.5) * slotWidth;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Row(
                  children: [
                    for (final item in _leftItems)
                      SizedBox(key: keys[item.tab], width: slotWidth, child: _NavButton(item: item, active: active, onSelect: onSelect)),
                    SizedBox(width: slotWidth), // reserved slot under the raised Chat button
                    for (final item in _rightItems)
                      SizedBox(key: keys[item.tab], width: slotWidth, child: _NavButton(item: item, active: active, onSelect: onSelect)),
                  ],
                ),
                Positioned(
                  top: -24,
                  left: fabCenterX - _fabSize / 2,
                  child: KeyedSubtree(
                    key: keys[_Tab.chat],
                    child: _ChatFab(active: active == _Tab.chat, onTap: () => onSelect(_Tab.chat)),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.active, required this.onSelect});

  final ({_Tab tab, String label, IconData icon, IconData iconFilled, Color color}) item;
  final _Tab active;
  final void Function(_Tab) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = active == item.tab;
    final color = selected ? item.color : theme.colorScheme.onSurfaceVariant;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: () => onSelect(item.tab),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // each tab has its own colour; the selected one sits in a pill
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? item.color.withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Icon(selected ? item.iconFilled : item.icon, color: color, size: 25),
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              style: TextStyle(fontFamily: displayFontFamily, fontSize: 11.5, fontWeight: selected ? FontWeight.w900 : FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatFab extends StatelessWidget {
  const _ChatFab({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Sage's face: Chat is where you talk to Sage (design v3).
    return Semantics(
      button: true,
      selected: active,
      label: 'Chat with Sage',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: active ? StudyOsColors.primary : const Color(0xFFDCE6FF), width: 3),
            boxShadow: [
              BoxShadow(color: StudyOsColors.primary.withValues(alpha: active ? 0.45 : 0.28), blurRadius: 16, offset: const Offset(0, 5)),
            ],
          ),
          child: const Padding(padding: EdgeInsets.fromLTRB(5, 3, 5, 7), child: SageMascot(size: 48)),
        ),
      ),
    );
  }
}
