import 'package:flutter/material.dart';

import '../../features/account/presentation/screens/account_screen.dart';
import '../../features/projects/presentation/screens/projects_list_screen.dart';
import '../auth/auth_service.dart';

/// A persistent entry point into Profile from every top-level screen's
/// top-right corner — added after Profile was dropped from the bottom nav
/// (2026-09-19, user request) in favor of keeping the nav bar to 4 flat
/// destinations either side of the raised Chat button. Self-contained
/// (owns its own navigation) so every call site is a one-line drop-in
/// rather than each screen threading an `onOpenProfile` callback through
/// from `AppShell`.
class ProfileIconButton extends StatelessWidget {
  const ProfileIconButton({super.key, required this.authService});

  final AuthService authService;

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AccountScreen(
          authService: authService,
          onOpenProjects: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => ProjectsListScreen(apiClient: authService.apiClient, authService: authService)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = authService.user;
    final displayName = (user?['display_name'] as String?)?.trim();
    final email = user?['email'] as String? ?? '';
    final initial = (displayName?.isNotEmpty ?? false) ? displayName![0].toUpperCase() : (email.isNotEmpty ? email[0].toUpperCase() : '?');

    return IconButton(
      tooltip: 'Profile',
      onPressed: () => _open(context),
      icon: CircleAvatar(
        radius: 15,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Text(
          initial,
          style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
    );
  }
}
