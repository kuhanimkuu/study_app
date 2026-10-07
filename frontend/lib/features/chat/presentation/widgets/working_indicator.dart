import 'dart:async';

import 'package:flutter/material.dart';

/// Shown under the transcript while an /api/ask/* call is in flight.
/// Replaces a bare 2px progress bar (2026-10-06): PDF, exam and flashcard
/// requests measured 1-4.5 minutes on the free local model, and with only
/// that bar for feedback the app looked frozen. Shows elapsed time, and
/// past [_slowAfter] explains that long answers are expected. Owns its
/// own timer so the chat screen doesn't rebuild every second.
class WorkingIndicator extends StatefulWidget {
  const WorkingIndicator({super.key});

  @override
  State<WorkingIndicator> createState() => _WorkingIndicatorState();
}

class _WorkingIndicatorState extends State<WorkingIndicator> {
  static const _slowAfter = Duration(seconds: 20);

  final _stopwatch = Stopwatch()..start();
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final elapsed = _stopwatch.elapsed;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const LinearProgressIndicator(minHeight: 2),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  elapsed < _slowAfter
                      ? 'Thinking… ${elapsed.inSeconds}s'
                      : 'Still working… ${elapsed.inSeconds}s — documents and flashcards can take a few '
                          'minutes. Keep the app open.',
                  style: muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
