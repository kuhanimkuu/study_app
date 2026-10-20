import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/widgets/gradient_button.dart';
import '../core/widgets/sage_mascot.dart';
import 'theme.dart';

/// The first-run guided tour (2026-10-19): the user asked to "show the
/// users what each feature does upon first sign up". The first time the
/// main app (AppShell) appears on a device — straight after signup and
/// the profile questions — Sage walks through each part of the app: the
/// screen dims, a spotlight moves from tab to tab, and a speech card says
/// what that part is for.
///
/// Shown once per device (SharedPreferences [_seenKey]). Profile → "Take
/// the app tour" replays it via [requestReplay].
class AppTour {
  AppTour._();

  static const _seenKey = 'app_tour_seen';

  /// Set by Profile's "Take the app tour"; AppShell listens and shows it.
  static final replayRequested = ValueNotifier<bool>(false);

  static Future<bool> shouldShow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return !(prefs.getBool(_seenKey) ?? false);
    } catch (_) {
      return false; // never block the app over a tour
    }
  }

  static Future<void> markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_seenKey, true);
    } catch (_) {}
  }

  static void requestReplay() => replayRequested.value = true;
}

/// One stop on the tour. [target] is the widget to spotlight; null shows
/// the card in the middle of the screen (welcome / finish).
class AppTourStep {
  const AppTourStep({required this.title, required this.body, required this.color, required this.icon, this.target, this.mood = SageMood.happy});

  final GlobalKey? target;
  final String title;
  final String body;
  final Color color;
  final IconData icon;
  final SageMood mood;
}

/// Full-screen overlay: a dimmed scrim with a spotlight cut around the
/// current step's target, and Sage's speech card beside it.
class AppTourOverlay extends StatefulWidget {
  const AppTourOverlay({super.key, required this.steps, required this.onDone});

  final List<AppTourStep> steps;
  final VoidCallback onDone;

  @override
  State<AppTourOverlay> createState() => _AppTourOverlayState();
}

class _AppTourOverlayState extends State<AppTourOverlay> {
  int _index = 0;

  /// Frames spent waiting for the current step's target to be laid out;
  /// past a few, the card just shows centred (e.g. the target isn't on
  /// screen) instead of re-checking on every frame forever.
  int _waitedFrames = 0;

  AppTourStep get _step => widget.steps[_index];
  bool get _isLast => _index == widget.steps.length - 1;

  void _next() {
    if (_isLast) {
      widget.onDone();
    } else {
      setState(() {
        _index++;
        _waitedFrames = 0;
      });
    }
  }

  void _back() {
    if (_index > 0) {
      setState(() {
        _index--;
        _waitedFrames = 0;
      });
    }
  }

  /// The target's rect in this overlay's coordinates, padded a little.
  Rect? _targetRect() {
    final targetBox = _step.target?.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox = context.findRenderObject() as RenderBox?;
    if (targetBox == null || overlayBox == null || !targetBox.hasSize || !targetBox.attached) return null;
    final topLeft = overlayBox.globalToLocal(targetBox.localToGlobal(Offset.zero));
    return (topLeft & targetBox.size).inflate(6);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // the target's position is only known after layout — read it on
        // the frame after a step changes
        final rect = _targetRect();
        if (rect == null && _step.target != null && _waitedFrames < 5) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _waitedFrames++);
          });
        }
        final size = constraints.biggest;
        final card = _SpeechCard(
          step: _step,
          index: _index,
          count: widget.steps.length,
          isLast: _isLast,
          onNext: _next,
          onBack: _index > 0 ? _back : null,
          onSkip: widget.onDone,
        );

        // card above a target in the lower half of the screen, below one
        // in the upper half; centred when there's no target
        Widget positioned;
        if (rect == null) {
          positioned = Center(child: Padding(padding: const EdgeInsets.all(20), child: card));
        } else if (rect.center.dy > size.height / 2) {
          positioned = Positioned(left: 16, right: 16, bottom: size.height - rect.top + 14, child: card);
        } else {
          positioned = Positioned(left: 16, right: 16, top: rect.bottom + 14, child: card);
        }

        return Stack(
          children: [
            // the scrim swallows taps so the app underneath can't be used mid-tour
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: CustomPaint(painter: _SpotlightPainter(rect, _step.color)),
              ),
            ),
            positioned,
          ],
        );
      },
    );
  }
}

class _SpeechCard extends StatelessWidget {
  const _SpeechCard({
    required this.step,
    required this.index,
    required this.count,
    required this.isLast,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  final AppTourStep step;
  final int index;
  final int count;
  final bool isLast;
  final VoidCallback onNext;
  final VoidCallback? onBack;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SageMascot(size: 64, mood: step.mood),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(step.icon, color: step.color, size: 20),
                          const SizedBox(width: 6),
                          Expanded(child: Text(step.title, style: theme.textTheme.titleLarge)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(step.body, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (var i = 0; i < count; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 4),
                    width: i == index ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == index ? step.color : theme.colorScheme.outline,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                const Spacer(),
                if (!isLast) TextButton(onPressed: onSkip, child: const Text('Skip tour')),
                if (onBack != null) IconButton(onPressed: onBack, tooltip: 'Back', icon: const Icon(Icons.arrow_back_rounded)),
                const SizedBox(width: 4),
                GradientButton(
                  label: isLast ? "Let's go!" : 'Next',
                  expand: false,
                  color: isLast ? StudyOsColors.success : step.color,
                  onPressed: onNext,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter(this.hole, this.color);

  final Rect? hole;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Paint()..color = const Color(0xCC060914);
    final full = Path()..addRect(Offset.zero & size);
    if (hole == null) {
      canvas.drawPath(full, scrim);
      return;
    }
    final spot = RRect.fromRectAndRadius(hole!, const Radius.circular(22));
    canvas.drawPath(Path.combine(PathOperation.difference, full, Path()..addRRect(spot)), scrim);
    canvas.drawRRect(
      spot,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.hole != hole || old.color != color;
}
