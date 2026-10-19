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
    // Said plainly up front (2026-10-19): AI answers need the student's own
    // key for now — the free local model isn't available yet.
    _IntroPage(
      tag: 'Bring your own AI key',
      icon: Icons.key_rounded,
      title: 'AI answers use\nyour own AI key',
      description:
          'Study OS connects to an AI provider you choose: DeepSeek, OpenAI or Anthropic (Claude). '
          'Add your API key in Profile → AI model after you sign up; you pay the provider directly for what you use. '
          'Your key is stored encrypted on this phone and is used only for your own questions.',
      note: 'Free built-in AI (no key needed) is still in development and not available yet. '
          'Your own flashcards, notes, study plans and progress tracking work without a key.',
      gradient: LinearGradient(colors: [StudyOsColors.primary, StudyOsColors.amber], begin: Alignment.topLeft, end: Alignment.bottomRight),
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
          'Ask questions in plain language, or start a guided session that explains a concept and checks your understanding as you go. '
          'Powered by your own AI key.',
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

  /// Index of the "Bring your own AI key" page — the banner jumps there.
  static const _byokPage = 1;

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
            _ByokBanner(
              onTap: () => _pageController.animateToPage(_byokPage, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut),
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
    // The text takes what it needs, up to ~2/3 of the height (scrolling
    // beyond that), and the illustration shrinks into the rest — the BYOK
    // page's longer copy overflowed a small phone by 340 px otherwise.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(24)),
                child: Center(
                  child: FittedBox(
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        gradient: page.gradient,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: StudyOsColors.primary.withValues(alpha: 0.25), blurRadius: 28, offset: const Offset(0, 12)),
                        ],
                      ),
                      child: Icon(page.icon, size: 54, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: constraints.maxHeight * 0.65),
              child: SingleChildScrollView(child: _buildPageText(theme, page)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageText(ThemeData theme, _IntroPage page) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(20)),
            child: Text(page.tag, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary, letterSpacing: 0.2)),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(page.title, textAlign: TextAlign.left, style: theme.textTheme.displaySmall),
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
        if (page.note != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: theme.colorScheme.tertiaryContainer, borderRadius: BorderRadius.circular(12)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.construction_rounded, size: 18, color: theme.colorScheme.onTertiaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    page.note!,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onTertiaryContainer, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
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
    this.note,
  });

  final String tag;
  final IconData icon;
  final String title;
  final String description;
  final Gradient gradient;

  /// A highlighted caveat under the description (e.g. "in development").
  final String? note;
}

/// Shown above every intro page, so even a student who taps Skip on the
/// first page knows AI answers need their own key. Tapping it opens the
/// page that explains how.
class _ByokBanner extends StatelessWidget {
  const _ByokBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Material(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.key_rounded, size: 18, color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'AI answers use your own API key (BYOK). Free built-in AI is still in development.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSecondaryContainer, fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 18, color: theme.colorScheme.onSecondaryContainer),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
