import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/sage_mascot.dart';
import '../../models/chat_message.dart';
import 'block_view.dart';

/// One entry in the chat transcript — a right-aligned bubble for what the
/// user sent, or a left-aligned bubble containing the moderator's rendered
/// blocks (see BlockView) for a response.
///
/// Design v3 (2026-10-19): replies come from Sage, the mascot — his face
/// sits beside each answer and the answer is a clean white card (the v2
/// grey bubble read as "system output", not a tutor talking to you).
class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message, required this.baseUrl, this.onStillStuck, this.onSetUpByok});

  final ChatMessage message;
  final String baseUrl;

  /// Fires when the user taps "still stuck on this?" — see
  /// ChatScreen._markStillStuck's doc comment. Null (and the affordance
  /// hidden) when this message has no `activity` to attach the report to.
  final VoidCallback? onStillStuck;

  /// Passed straight through to BlockView — see its own doc comment.
  final VoidCallback? onSetUpByok;

  @override
  Widget build(BuildContext context) {
    if (message.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(6),
            ),
            boxShadow: const [BoxShadow(color: StudyOsColors.primaryLedge, offset: Offset(0, 3))],
          ),
          child: Text(message.userText ?? '', style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4)),
        ),
      );
    }
    if (message.errorText != null) {
      return BlockView(block: {'type': 'error', 'message': message.errorText}, baseUrl: baseUrl);
    }

    final topic = message.activity?['topic'] as String?;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SageAvatar(),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border.all(color: theme.colorScheme.outline, width: 1.5),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final block in (message.blocks ?? []))
                    BlockView(block: block as Map<String, dynamic>, baseUrl: baseUrl, onSetUpByok: onSetUpByok),
                  if (topic != null) ...[
                    const SizedBox(height: 4),
                    message.struggleMarked
                        ? Text(
                            'Noted — added to History',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.primary),
                          )
                        : TextButton.icon(
                            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
                            onPressed: onStillStuck,
                            icon: const Icon(Icons.flag_outlined, size: 16),
                            label: const Text('Still stuck on this?'),
                          ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sage's face in a little circle, beside each of his replies and in the
/// chat header.
class SageAvatar extends StatelessWidget {
  const SageAvatar({super.key, this.size = 34, this.mood = SageMood.happy});

  final double size;
  final SageMood mood;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.fromLTRB(size * 0.06, size * 0.02, size * 0.06, size * 0.1),
      decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, shape: BoxShape.circle),
      child: SageMascot(size: size, mood: mood),
    );
  }
}
