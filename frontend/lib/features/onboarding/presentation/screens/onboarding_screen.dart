import 'package:flutter/material.dart';

import '../../../../core/auth/auth_service.dart';
import '../../../../core/widgets/brand_wordmark.dart';
import '../../../../core/widgets/gradient_button.dart';

/// Shown once, immediately after signup (see AuthService.justSignedUp) —
/// never a gate the student must pass through, per blueprint Section 5
/// ("a student should be able to sign in and immediately start
/// studying"). Every field is optional and skippable; reuses the exact
/// same updateStudentProfile() call the Account screen's own "Student
/// profile" section already uses, so filling this in now vs. later in
/// Account is the same data, not a separate onboarding-only record.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _educationLevelController = TextEditingController();
  final _courseController = TextEditingController();
  final _dailyStudyTargetController = TextEditingController();
  bool _isSaving = false;
  String? _error;

  void _skip() => widget.authService.dismissOnboarding();

  Future<void> _getStarted() async {
    final educationLevel = _educationLevelController.text.trim();
    final course = _courseController.text.trim();
    final targetText = _dailyStudyTargetController.text.trim();

    if (educationLevel.isEmpty && course.isEmpty && targetText.isEmpty) {
      _skip();
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await widget.authService.updateStudentProfile(
        educationLevel: educationLevel.isEmpty ? null : educationLevel,
        course: course.isEmpty ? null : course,
        dailyStudyTargetMinutes: targetText.isEmpty ? null : int.tryParse(targetText),
      );
      _skip();
    } on Exception catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        actions: [TextButton(onPressed: _skip, child: const Text('Skip'))],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Welcome to', style: Theme.of(context).textTheme.bodyLarge),
            BrandWordmark(style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Optional — you can start studying right away and fill this in later from Account.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _educationLevelController,
              decoration: const InputDecoration(labelText: 'Education level', hintText: 'e.g. Undergraduate'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _courseController,
              decoration: const InputDecoration(labelText: 'Course / program'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _dailyStudyTargetController,
              decoration: const InputDecoration(labelText: 'Daily study target (minutes)'),
              keyboardType: TextInputType.number,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 24),
            GradientButton(label: 'Get started', isLoading: _isSaving, onPressed: _isSaving ? null : _getStarted),
          ],
        ),
      ),
    );
  }
}
