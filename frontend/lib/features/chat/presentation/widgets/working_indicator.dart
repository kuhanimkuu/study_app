import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/widgets/sage_mascot.dart';
import 'message_bubble.dart';

/// Shown under the transcript while an /api/ask/* call is in flight.
/// Replaced a bare 2px progress bar (2026-10-06): PDF, exam and flashcard
/// requests measured 1-4.5 minutes on the free local model, and with only
/// that bar for feedback the app looked frozen. Shows elapsed time, and
/// past [_slowAfter] explains that long answers are expected. Owns its
/// own timer so the chat screen doesn't rebuild every second.
///
/// Design v3 (2026-10-19): Sage, thinking, with a "typing" bubble of
/// bouncing dots — the reply visibly coming from him.
class WorkingIndicator extends StatefulWidget {
  const WorkingIndicator({super.key});

  @override
  State<WorkingIndicator> createState() => _WorkingIndicatorState();
}

class _WorkingIndicatorState extends State<WorkingIndicator> with SingleTickerProviderStateMixin {
  static const _slowAfter = Duration(seconds: 20);

  final _stopwatch = Stopwatch()..start();
  late final Timer _ticker;
  late final AnimationController _dots = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _ticker.cancel();
    _dots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final elapsed = _stopwatch.elapsed;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SageAvatar(mood: SageMood.thinking),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border.all(color: theme.colorScheme.outline, width: 1.5),
              borderRadius: BorderRadius.circular(18),
            ),
            child: AnimatedBuilder(
              animation: _dots,
              builder: (context, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++)
                    Transform.translate(
                      offset: Offset(0, -4 * math.max(0, math.sin((_dots.value * 2 * math.pi) - i * 0.9))),
                      child: Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              elapsed < _slowAfter
                  ? 'Sage is thinking… ${elapsed.inSeconds}s'
                  : 'Still working… ${elapsed.inSeconds}s — documents and flashcards can take a few minutes. Keep the app open.',
              style: muted,
            ),
          ),
        ],
      ),
    );
  }
}
