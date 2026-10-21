import 'package:flutter/material.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/auth/auth_service.dart';
import '../../../../core/widgets/gradient_button.dart';

/// "Forgot password?" (2026-10-21): the server emails a 6-digit code
/// (server/domains/identity/router.py); entering it with a new password
/// signs the student in and signs out every other device.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, required this.authService, this.initialEmail = ''});

  final AuthService authService;
  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final _emailController = TextEditingController(text: widget.initialEmail);
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _repeatController = TextEditingController();
  bool _codeSent = false;
  bool _isLoading = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    for (final c in [_emailController, _codeController, _passwordController, _repeatController]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Enter the email you signed up with.');
      return;
    }
    await _run(() async {
      final message = await widget.authService.apiClient.requestPasswordReset(email);
      setState(() {
        _codeSent = true;
        _info = message;
      });
    });
  }

  Future<void> _reset() async {
    String? problem;
    if (!RegExp(r'^\d{6}$').hasMatch(_codeController.text.trim())) problem = 'Enter the 6-digit code from the email.';
    if (_passwordController.text.length < 8) problem ??= 'The new password needs at least 8 characters.';
    if (_passwordController.text != _repeatController.text) problem ??= "The two passwords don't match.";
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    await _run(() async {
      await widget.authService.resetPassword(
        email: _emailController.text.trim(),
        code: _codeController.text.trim(),
        newPassword: _passwordController.text,
      );
      // Signed in: AuthGate shows the app underneath; close this screen.
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: [
            Text(
              _codeSent
                  ? 'Enter the code we emailed you and choose a new password.'
                  : "Enter your account's email and we'll send you a 6-digit code.",
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _emailController,
              enabled: !_codeSent,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded)),
            ),
            if (_codeSent) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofocus: true,
                decoration: const InputDecoration(labelText: '6-digit code', prefixIcon: Icon(Icons.pin_outlined), counterText: ''),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New password',
                  helperText: '8 to 72 characters',
                  prefixIcon: Icon(Icons.lock_outline_rounded),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _repeatController,
                obscureText: true,
                onSubmitted: (_) => _reset(),
                decoration: const InputDecoration(labelText: 'New password again', prefixIcon: Icon(Icons.lock_outline_rounded)),
              ),
            ],
            if (_info != null && _error == null) ...[
              const SizedBox(height: 12),
              Text(_info!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            GradientButton(
              label: _codeSent ? 'Set new password' : 'Send code',
              isLoading: _isLoading,
              onPressed: _isLoading ? null : (_codeSent ? _reset : _sendCode),
            ),
            if (_codeSent)
              TextButton(
                onPressed: _isLoading
                    ? null
                    : () => setState(() {
                          _codeSent = false;
                          _info = null;
                          _error = null;
                        }),
                child: const Text('Use a different email or send a new code'),
              ),
          ],
        ),
      ),
    );
  }
}
