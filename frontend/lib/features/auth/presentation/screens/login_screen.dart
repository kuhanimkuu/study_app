import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/auth/auth_service.dart';
import '../../../../core/widgets/gradient_button.dart';
import '../../../chat/presentation/widgets/server_settings_dialog.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  String? _error;

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await widget.authService.login(email: _emailController.text.trim(), password: _passwordController.text);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log in'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: widget.authService.apiClient.baseUrl,
            onPressed: _openServerSettings,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                  onSubmitted: (_) => _login(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 20),
                GradientButton(
                  label: 'Log in',
                  isLoading: _isLoading,
                  onPressed: _isLoading ? null : _login,
                ),
                const SizedBox(height: 12),
                const Row(
                  children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('or')), Expanded(child: Divider())],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _isGoogleLoading ? null : _loginWithGoogle,
                  icon: _isGoogleLoading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text('G', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
                  label: const Text('Continue with Google'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => SignupScreen(authService: widget.authService)),
                  ),
                  child: const Text("Don't have an account? Sign up"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
