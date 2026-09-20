import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/auth/auth_service.dart';
import '../../../../core/widgets/cold_start_hint.dart';
import '../../../../core/widgets/gradient_button.dart';
import '../../../chat/presentation/widgets/server_settings_dialog.dart';
import 'signup_screen.dart';

/// Matches the approved visual reference's `Auth.tsx`: a soft gradient
/// hero panel (logo + tagline) above a plain-surface form area with
/// icon-prefixed fields, a gradient primary button, a divider, and a
/// bordered Google button — this screen had no design pass at all before
/// this slice (every earlier UI phase's own "still open" list never
/// mentioned it).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with ColdStartHintMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;
  String? _error;

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    startColdStartTimer();
    try {
      await widget.authService.login(email: _emailController.text.trim(), password: _passwordController.text);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      cancelColdStartTimer();
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() {
      _isGoogleLoading = true;
      _error = null;
    });
    try {
      await widget.authService.signInWithGoogle();
      // AuthGate (listening to authService) swaps to the app shell
      // automatically once this succeeds — nothing else to do here.
    } on GoogleSignInException catch (e) {
      // A user backing out of the account picker isn't an error worth
      // surfacing — every other GoogleSignInException code is.
      if (e.code != GoogleSignInExceptionCode.canceled) {
        setState(() => _error = 'Google sign-in failed: ${e.description ?? e.code}');
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  Future<void> _openServerSettings() async {
    final newUrl = await showServerSettingsDialog(context, widget.authService.apiClient.baseUrl);
    if (newUrl == null || newUrl.isEmpty) return;
    setState(() => widget.authService.apiClient.baseUrl = newUrl);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          children: [
            // Hero panel
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 36),
              decoration: BoxDecoration(gradient: StudyOsColors.heroPanel(theme.brightness)),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      icon: Icon(Icons.settings_outlined, color: theme.colorScheme.onSurfaceVariant),
                      tooltip: widget.authService.apiClient.baseUrl,
                      onPressed: _openServerSettings,
                    ),
                  ),
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: StudyOsColors.brandGradient,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [BoxShadow(color: StudyOsColors.primary.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 4))],
                    ),
                    child: const Icon(Icons.auto_stories_rounded, color: Colors.white, size: 30),
                  ),
                  const SizedBox(height: 16),
                  Text('Study OS', style: theme.textTheme.headlineLarge),
                  const SizedBox(height: 4),
                  Text(
                    'AI COMPANION',
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, letterSpacing: 2),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Your intelligent study companion. Powered by AI, private by default.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.5),
                  ),
                ],
              ),
            ),
            // Form area
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Welcome back', style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded)),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    onSubmitted: (_) => _login(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  buildColdStartHint(context),
                  const SizedBox(height: 20),
                  GradientButton(label: 'Sign in', isLoading: _isLoading, onPressed: _isLoading ? null : _login),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(child: Divider(color: theme.colorScheme.outline)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('or continue with', style: theme.textTheme.bodySmall),
                      ),
                      Expanded(child: Divider(color: theme.colorScheme.outline)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: _isGoogleLoading ? null : _loginWithGoogle,
                      icon: _isGoogleLoading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.g_mobiledata_rounded, size: 26, color: StudyOsColors.primary),
                      label: const Text('Continue with Google'),
                      style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => SignupScreen(authService: widget.authService)),
                      ),
                      child: RichText(
                        text: TextSpan(
                          style: theme.textTheme.bodySmall,
                          children: [
                            const TextSpan(text: 'No account? '),
                            TextSpan(text: 'Create one free', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
