import 'package:flutter/material.dart';

import 'theme.dart';

/// Shown while `AuthGate` is restoring a saved session. Matches the
/// approved visual reference's `Splash.tsx` closely: a soft radial glow
/// behind a pulsing rounded logo mark, the wordmark + tagline, three
/// bouncing loading dots, and a small caption pinned near the bottom.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      // Without SafeArea, the bottom caption's offset is measured from the
      // raw screen edge — on a real device with on-screen (button or
      // gesture) navigation, that lands the caption partly underneath the
      // nav bar instead of above it (found from a real-device screenshot,
      // 2026-09-19).
      body: SafeArea(
        child: Column(
          children: [
            // The logo/wordmark block is centered in the space ABOVE the
            // caption, not the full screen — the previous version used a
            // `Stack` with `alignment: Alignment.center`, which centers
            // against the *entire* container including the caption's own
            // space at the bottom, visually pushing the block above true
            // center (a real, reported defect, distinct from the SafeArea
            // fix above — both were needed). `Expanded` + `Center` here
            // measures against only the space actually available to it.
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        // Radial glow behind the logo.
                        Container(
                          width: 300,
                          height: 300,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [StudyOsColors.primary.withValues(alpha: isDark ? 0.14 : 0.09), Colors.transparent],
                            ),
                          ),
                        ),
                        AnimatedBuilder(
                          animation: _pulse,
                          builder: (context, child) {
                            final t = _pulse.value;
                            final ringAlpha = (0.35 * (1 - t)).clamp(0.0, 1.0);
                            return Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: StudyOsColors.primary.withValues(alpha: ringAlpha),
                                    spreadRadius: 18 * t,
                                  ),
                                ],
                              ),
                              child: child,
                            );
                          },
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              gradient: StudyOsColors.brandGradient,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(color: StudyOsColors.primary.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 4)),
                              ],
                            ),
                            child: const Icon(Icons.auto_stories_rounded, color: Colors.white, size: 34),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Study OS',
                      style: theme.textTheme.displaySmall?.copyWith(letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your AI study companion',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, letterSpacing: 0.3),
                    ),
                    const SizedBox(height: 60),
                    _ThinkingDots(animation: _pulse),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Text(
                'YOUR STUDY, YOUR PACE',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThinkingDots extends StatelessWidget {
  const _ThinkingDots({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (animation.value * 3 - i) % 3;
            final bounce = phase >= 0 && phase < 1 ? (1 - (phase - 0.5).abs() * 2) : 0.0;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 6,
              height: 6,
              transform: Matrix4.translationValues(0, -5 * bounce, 0),
              decoration: const BoxDecoration(color: StudyOsColors.primary, shape: BoxShape.circle),
            );
          }),
        );
      },
    );
  }
}
