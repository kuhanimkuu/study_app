import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import 'block_view.dart';

/// One entry in the chat transcript — a right-aligned bubble for what the
/// user sent, or a left-aligned bubble containing the moderator's rendered
/// blocks (see BlockView) for a response.
class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message, required this.baseUrl, this.onStillStuck});

  final ChatMessage message;
  final String baseUrl;

  /// Fires when the user taps "still stuck on this?" — see
  /// ChatScreen._markStillStuck's doc comment. Null (and the affordance
  /// hidden) when this message has no `activity` to attach the report to.
  final VoidCallback? onStillStuck;

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
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Text(message.userText ?? '', style: const TextStyle(color: Colors.white)),
        ),
      );
    }
    if (message.errorText != null) {
      return BlockView(block: {'type': 'error', 'message': message.errorText}, baseUrl: baseUrl);
    }

    final topic = message.activity?['topic'] as String?;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final block in (message.blocks ?? []))
              BlockView(block: block as Map<String, dynamic>, baseUrl: baseUrl),
            if (topic != null) ...[
              const SizedBox(height: 4),
              message.struggleMarked
                  ? Text(
                      'Noted — added to History',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
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
    );
  }
}
