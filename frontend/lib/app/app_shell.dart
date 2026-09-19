import 'package:flutter/material.dart';

import '../core/auth/auth_service.dart';
import '../features/chat/chat_quick_action.dart';
import '../features/chat/presentation/screens/chat_screen.dart';
import '../features/home/presentation/screens/home_screen.dart';
import '../features/learning/concepts/presentation/screens/learn_hub_screen.dart';
import '../features/planner/presentation/screens/planner_screen.dart';
import '../features/projects/presentation/screens/projects_list_screen.dart';
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

  void _select(_Tab tab) => setState(() => _tab = tab);

  void _runChatQuickAction(ChatQuickAction action) {
    _chatQuickAction.value = action;
    _select(_Tab.chat);
  }

  @override
  void dispose() {
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
        onQuickAction: _runChatQuickAction,
      ),
      _Tab.projects: ProjectsListScreen(apiClient: widget.authService.apiClient, authService: widget.authService),
      _Tab.learn: LearnHubScreen(apiClient: widget.authService.apiClient, authService: widget.authService),
      _Tab.chat: ChatScreen(authService: widget.authService, pendingAction: _chatQuickAction),
      _Tab.planner: PlannerScreen(apiClient: widget.authService.apiClient, authService: widget.authService),
    };

    return Scaffold(
      body: IndexedStack(
        index: _Tab.values.indexOf(_tab),
        children: [for (final t in _Tab.values) screens[t]!],
      ),
      bottomNavigationBar: _StudyOsBottomNav(active: _tab, onSelect: _select),
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
  const _StudyOsBottomNav({required this.active, required this.onSelect});

  final _Tab active;
  final void Function(_Tab) onSelect;

  static const _leftItems = [
    (tab: _Tab.home, label: 'Home', icon: Icons.home_outlined, iconFilled: Icons.home_rounded),
    (tab: _Tab.projects, label: 'Projects', icon: Icons.folder_outlined, iconFilled: Icons.folder_rounded),
  ];
  static const _rightItems = [
    (tab: _Tab.learn, label: 'Learn', icon: Icons.school_outlined, iconFilled: Icons.school_rounded),
    (tab: _Tab.planner, label: 'Planner', icon: Icons.calendar_month_outlined, iconFilled: Icons.calendar_month_rounded),
  ];
  static const _totalSlots = 5; // 2 left items + 1 gap slot (for the FAB) + 2 right items
  static const _fabSize = 56.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Container(
        height: 68,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(top: BorderSide(color: theme.colorScheme.outline)),
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
                      SizedBox(width: slotWidth, child: _NavButton(item: item, active: active, onSelect: onSelect)),
                    SizedBox(width: slotWidth), // reserved slot under the raised Chat button
                    for (final item in _rightItems)
                      SizedBox(width: slotWidth, child: _NavButton(item: item, active: active, onSelect: onSelect)),
                  ],
                ),
                Positioned(
                  top: -20,
                  left: fabCenterX - _fabSize / 2,
                  child: _ChatFab(active: active == _Tab.chat, onTap: () => onSelect(_Tab.chat)),
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

  final ({_Tab tab, String label, IconData icon, IconData iconFilled}) item;
  final _Tab active;
  final void Function(_Tab) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = active == item.tab;
    final color = selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: () => onSelect(item.tab),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(selected ? item.iconFilled : item.icon, color: color, size: 22),
          const SizedBox(height: 3),
          Text(
            item.label,
            style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
          ),
        ],
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          gradient: StudyOsColors.brandGradient,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: StudyOsColors.primary.withValues(alpha: active ? 0.5 : 0.35),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 24),
      ),
    );
  }
}
