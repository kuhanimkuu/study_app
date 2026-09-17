import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/auth/auth_service.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/intro/presentation/screens/feature_intro_screen.dart';
import '../features/onboarding/presentation/screens/onboarding_screen.dart';
import 'app_shell.dart';
import 'splash_screen.dart';

/// Root decision point: restores any saved session on first build, then
/// shows either the login screen or the authenticated app shell —
/// swapping automatically whenever AuthService's state changes (login,
/// signup, logout), since it's a ChangeNotifier this widget listens to.
/// Also gates a once-ever feature tour (`FeatureIntroScreen`) in front of
/// the login screen for a device that has never seen it, tracked by a
/// `shared_preferences` flag rather than AuthService state, since it's
/// about this device/install, not this account.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.authService});

  final AuthService authService;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  /// null while the flag is still being read from disk.
  bool? _introSeen;

  @override
  void initState() {
    super.initState();
    widget.authService.addListener(_onAuthChanged);
    widget.authService.restoreSession();
    _loadIntroSeen();
  }

  Future<void> _loadIntroSeen() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _introSeen = prefs.getBool('intro_seen') ?? false);
  }

  void _onIntroDone() => setState(() => _introSeen = true);

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
    if (!widget.authService.initialized || _introSeen == null) {
      return const SplashScreen();
    }
    if (!widget.authService.isAuthenticated) {
      if (!_introSeen!) {
        return FeatureIntroScreen(onDone: _onIntroDone);
      }
      return LoginScreen(authService: widget.authService);
    }
    if (widget.authService.justSignedUp) {
      return OnboardingScreen(authService: widget.authService);
    }
    return AppShell(authService: widget.authService);
  }
}
