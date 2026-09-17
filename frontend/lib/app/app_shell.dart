import 'package:flutter/material.dart';

import '../core/auth/auth_service.dart';
import '../features/account/presentation/screens/account_screen.dart';
import '../features/chat/presentation/screens/chat_screen.dart';
import '../features/history/presentation/screens/history_screen.dart';
import '../features/home/presentation/screens/home_screen.dart';
import '../features/planner/presentation/screens/planner_screen.dart';
import '../features/projects/presentation/screens/projects_list_screen.dart';
import 'theme.dart';

/// Shown once the user is authenticated — bottom nav switching between the
/// top-level screens. AuthGate decides whether this or the login/signup
/// flow is on screen; this widget doesn't know about that decision.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.authService});

  final AuthService authService;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _projectsIndex = 1;
  static const _plannerIndex = 3;
  static const _tabCount = 6;

  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(
        apiClient: widget.authService.apiClient,
        onOpenPlanner: () => setState(() => _index = _plannerIndex),
        onOpenProjects: () => setState(() => _index = _projectsIndex),
      ),
      ProjectsListScreen(apiClient: widget.authService.apiClient),
      ChatScreen(authService: widget.authService),
      PlannerScreen(apiClient: widget.authService.apiClient),
      HistoryScreen(apiClient: widget.authService.apiClient),
      AccountScreen(authService: widget.authService),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      // A thin gradient bar slides above the active tab (the design
      // system's one signature "brand" touch on chrome that's on screen
      // at all times — see StudyOsColors.brandGradient) instead of the
      // default filled-pill indicator.
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).dividerColor, width: 0.5))),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                top: 0,
                left: MediaQuery.of(context).size.width / _tabCount * _index,
                child: Container(
                  width: MediaQuery.of(context).size.width / _tabCount,
                  height: 3,
                  decoration: const BoxDecoration(
                    gradient: StudyOsColors.brandGradient,
                    borderRadius: BorderRadius.only(bottomLeft: Radius.circular(3), bottomRight: Radius.circular(3)),
                  ),
                ),
              ),
              NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                backgroundColor: Colors.transparent,
                indicatorColor: Colors.transparent,
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
                  NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'Projects'),
                  NavigationDestination(icon: Icon(Icons.chat_outlined), selectedIcon: Icon(Icons.chat), label: 'Chat'),
                  NavigationDestination(
                    icon: Icon(Icons.calendar_month_outlined),
                    selectedIcon: Icon(Icons.calendar_month),
                    label: 'Planner',
                  ),
                  NavigationDestination(icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history), label: 'History'),
                  NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Account'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
