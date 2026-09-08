import 'package:flutter/material.dart';

import '../core/auth/auth_service.dart';
import '../features/account/presentation/screens/account_screen.dart';
import '../features/chat/presentation/screens/chat_screen.dart';
import '../features/history/presentation/screens/history_screen.dart';
import '../features/projects/presentation/screens/projects_list_screen.dart';

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
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      ProjectsListScreen(apiClient: widget.authService.apiClient),
      ChatScreen(authService: widget.authService),
      HistoryScreen(apiClient: widget.authService.apiClient),
      AccountScreen(authService: widget.authService),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'Projects'),
          NavigationDestination(icon: Icon(Icons.chat_outlined), selectedIcon: Icon(Icons.chat), label: 'Chat'),
          NavigationDestination(icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history), label: 'History'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Account'),
        ],
      ),
    );
  }
}
