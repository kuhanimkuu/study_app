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
      tag: 'Ask anything',
      icon: Icons.psychology_alt_rounded,
      title: 'Concepts that stick',
      description:
          'Study OS tracks your mastery of every concept and schedules reviews with spaced repetition (FSRS) — so you revisit things right before you\'d forget them.',
      gradient: StudyOsColors.brandGradient,
    ),
    _IntroPage(
      tag: 'Practice your way',
      icon: Icons.style_rounded,
      title: 'Flashcards, quizzes,\nand 10 question types',
      description:
          'From multiple choice to open response. Run a quiz, or switch on exam mode to test yourself for real.',
      gradient: LinearGradient(colors: [StudyOsColors.amber, StudyOsColors.primary], begin: Alignment.topLeft, end: Alignment.bottomRight),
    ),
    _IntroPage(
      tag: 'An AI study moderator',
      icon: Icons.forum_rounded,
      title: 'Ask in plain language,\nget deep answers',
      description:
          'Ask questions in plain language, or start a guided session that explains a concept and checks your understanding as you go.',
      gradient: LinearGradient(colors: [StudyOsColors.primaryDark, StudyOsColors.primary], begin: Alignment.topLeft, end: Alignment.bottomRight),
    ),
    _IntroPage(
      tag: 'Plan it, track it',
      icon: Icons.insights_rounded,
      title: 'See your progress,\nnot just your grades',
      description:
          'Set goals, schedule study sessions on a calendar, and watch your streak and accuracy grow on the Progress screen.',
      gradient: LinearGradient(colors: [StudyOsColors.amber, StudyOsColors.primaryDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
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
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Center(
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    gradient: page.gradient,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: StudyOsColors.primary.withValues(alpha: 0.25), blurRadius: 28, offset: const Offset(0, 12))],
                  ),
                  child: Icon(page.icon, size: 54, color: Colors.white),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                page.tag,
                style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary, letterSpacing: 0.2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              page.title,
              textAlign: TextAlign.left,
              style: theme.textTheme.displaySmall,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              page.description,
              textAlign: TextAlign.left,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(BuildContext context, int index) {
    final active = index == _currentPage;
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.symmetric(horizontal: 3),
      width: active ? 20 : 6,
      height: 6,
      decoration: BoxDecoration(
        color: active ? theme.colorScheme.primary : theme.colorScheme.outline,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

class _IntroPage {
  const _IntroPage({
    required this.tag,
    required this.icon,
    required this.title,
    required this.description,
    required this.gradient,
  });

  final String tag;
  final IconData icon;
  final String title;
  final String description;
  final Gradient gradient;
}
