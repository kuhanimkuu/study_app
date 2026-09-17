import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/theme.dart';

/// Shown once, ever, on first launch before the user has an account —
/// a feature tour, gated by a `shared_preferences` flag (`intro_seen`),
/// distinct from `features/onboarding/`'s post-signup student-profile
/// screen. Same anatomy as Nexora's `OnboardingScreen`: skip button,
/// a swipeable `PageView` of gradient icon badges + title + description,
/// a dot indicator, and a final "Get Started" CTA — content rewritten
/// for Study OS's actual pillars instead of Nexora's social features.
class FeatureIntroScreen extends StatefulWidget {
  const FeatureIntroScreen({super.key, required this.onDone});

  /// Called once the user skips or finishes the tour — the caller
  /// (AuthGate) re-checks the persisted flag and swaps to LoginScreen.
  final VoidCallback onDone;

  @override
  State<FeatureIntroScreen> createState() => _FeatureIntroScreenState();
}

class _FeatureIntroScreenState extends State<FeatureIntroScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  static const _pages = [
    _IntroPage(
      icon: Icons.psychology_alt_rounded,
      title: 'Concepts that stick',
      description:
          'Study OS tracks your mastery of every concept and schedules reviews with spaced repetition (FSRS) — so you revisit things right before you\'d forget them.',
      gradient: LinearGradient(colors: [StudyOsColors.primary, StudyOsColors.primaryLight], begin: Alignment.topLeft, end: Alignment.bottomRight),
    ),
    _IntroPage(
      icon: Icons.style_rounded,
      title: 'Practice your way',
      description:
          'Flashcards, notes, and 10 question types — from multiple choice to open response. Run a quiz, or switch on exam mode to test yourself for real.',
      gradient: LinearGradient(colors: [StudyOsColors.accent, StudyOsColors.accentLight], begin: Alignment.topLeft, end: Alignment.bottomRight),
    ),
    _IntroPage(
      icon: Icons.forum_rounded,
      title: 'An AI study moderator',
      description:
          'Ask questions in plain language, or start a guided session that explains a concept and checks your understanding as you go.',
      gradient: LinearGradient(colors: [StudyOsColors.primaryDark, StudyOsColors.primary], begin: Alignment.topLeft, end: Alignment.bottomRight),
    ),
    _IntroPage(
      icon: Icons.insights_rounded,
      title: 'Plan it, track it',
      description:
          'Set goals, schedule study sessions on a calendar, and watch your streak and accuracy grow on the Progress screen.',
      gradient: LinearGradient(colors: [StudyOsColors.accentDark, StudyOsColors.accent], begin: Alignment.topLeft, end: Alignment.bottomRight),
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('intro_seen', true);
    widget.onDone();
  }

  void _next() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLast = _currentPage == _pages.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: TextButton(onPressed: _finish, child: const Text('Skip')),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemCount: _pages.length,
                itemBuilder: (context, i) => _buildPage(context, _pages[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (i) => _buildDot(context, i)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    isLast ? 'Get started' : 'Next',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(BuildContext context, _IntroPage page) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              gradient: page.gradient,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: StudyOsColors.primary.withValues(alpha: 0.25), blurRadius: 28, offset: const Offset(0, 12))],
            ),
            child: Icon(page.icon, size: 72, color: Colors.white),
          ),
          const SizedBox(height: 40),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          Text(
            page.description,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(BuildContext context, int index) {
    final active = index == _currentPage;
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: active ? 28 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: active ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _IntroPage {
  const _IntroPage({required this.icon, required this.title, required this.description, required this.gradient});

  final IconData icon;
  final String title;
  final String description;
  final Gradient gradient;
}
