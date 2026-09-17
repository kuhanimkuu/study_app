import 'package:flutter/material.dart';

import '../core/widgets/brand_wordmark.dart';
import 'theme.dart';

/// Shown while `AuthGate` is restoring a saved session (`AuthService`'s
/// startup `SecureStorage` read) — same shape as Nexora's
/// `LoadingSplashScreen`: a rounded logo mark, a gradient wordmark, a
/// tagline, and a spinner. No native launch-screen asset exists yet, so
/// this is a pure-Flutter splash rather than a native one.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: StudyOsColors.brandGradient,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(color: StudyOsColors.primary.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 8)),
                ],
              ),
              child: const Center(
                child: Icon(Icons.school_rounded, color: Colors.white, size: 60),
              ),
            ),
            const SizedBox(height: 28),
            BrandWordmark(
              style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: 4),
            ),
            const SizedBox(height: 8),
            Text(
              'Your AI-powered study companion.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 40),
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 3, valueColor: AlwaysStoppedAnimation(StudyOsColors.primary)),
            ),
          ],
        ),
      ),
    );
  }
}
