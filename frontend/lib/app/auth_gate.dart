import 'package:flutter/material.dart';

import '../core/auth/auth_service.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import 'app_shell.dart';

/// Root decision point: restores any saved session on first build, then
/// shows either the login screen or the authenticated app shell —
/// swapping automatically whenever AuthService's state changes (login,
/// signup, logout), since it's a ChangeNotifier this widget listens to.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.authService});

  final AuthService authService;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    widget.authService.addListener(_onAuthChanged);
    widget.authService.restoreSession();
  }

  @override
  void dispose() {
    widget.authService.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.authService.initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!widget.authService.isAuthenticated) {
      return LoginScreen(authService: widget.authService);
    }
    return AppShell(authService: widget.authService);
  }
}
