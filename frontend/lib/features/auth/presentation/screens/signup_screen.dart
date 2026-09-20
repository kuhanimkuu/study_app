import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/auth/auth_service.dart';
import '../../../../core/widgets/cold_start_hint.dart';
import '../../../../core/widgets/gradient_button.dart';
import 'legal_screen.dart';

/// Same hero-panel + icon-prefixed-field anatomy as `LoginScreen`, one
/// extra optional name field.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> with ColdStartHintMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _agreedToTerms = false;
  String? _error;

  void _openLegal(LegalDocumentKind kind) {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => LegalScreen(kind: kind)));
  }

  Future<void> _signup() async {
    if (!_agreedToTerms) {
      setState(() => _error = 'Please agree to the Terms of Service and Privacy Policy to continue.');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    startColdStartTimer();
    try {
      await widget.authService.signup(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        displayName: _displayNameController.text.trim().isEmpty ? null : _displayNameController.text.trim(),
      );
      // AuthGate (listening to authService) will swap to the app shell
      // automatically once signup succeeds — nothing else to do here.
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      cancelColdStartTimer();
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(32, 20, 32, 32),
              decoration: BoxDecoration(gradient: StudyOsColors.heroPanel(theme.brightness)),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: BackButton(onPressed: () => Navigator.of(context).pop()),
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
                  Text('Create your account', style: theme.textTheme.headlineLarge, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    'Free to start — bring your own AI key any time.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _displayNameController,
                    decoration: const InputDecoration(labelText: 'Name (optional)', prefixIcon: Icon(Icons.person_outline_rounded)),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded)),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    onSubmitted: (_) => _signup(),
                    decoration: InputDecoration(
                      labelText: 'Password (min 8 characters)',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  InkWell(
                    onTap: () => setState(() => _agreedToTerms = !_agreedToTerms),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(value: _agreedToTerms, onChanged: (v) => setState(() => _agreedToTerms = v ?? false)),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: RichText(
                                text: TextSpan(
                                  style: theme.textTheme.bodySmall,
                                  children: [
                                    const TextSpan(text: 'I agree to the '),
                                    TextSpan(
                                      text: 'Terms of Service',
                                      style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
                                      recognizer: TapGestureRecognizer()..onTap = () => _openLegal(LegalDocumentKind.terms),
                                    ),
                                    const TextSpan(text: ' and '),
                                    TextSpan(
                                      text: 'Privacy Policy',
                                      style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
                                      recognizer: TapGestureRecognizer()..onTap = () => _openLegal(LegalDocumentKind.privacy),
                                    ),
                                    const TextSpan(text: '.'),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  buildColdStartHint(context),
                  const SizedBox(height: 16),
                  GradientButton(label: 'Create account', isLoading: _isLoading, onPressed: _isLoading ? null : _signup),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
