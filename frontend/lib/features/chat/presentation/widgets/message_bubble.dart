import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/sage_mascot.dart';
import '../../models/chat_message.dart';
import 'block_view.dart';
import 'message_actions.dart';

/// One entry in the chat transcript — a right-aligned bubble for what the
/// user sent, or a left-aligned bubble containing the moderator's rendered
/// blocks (see BlockView) for a response.
///
/// Design v3 (2026-10-19): replies come from Sage, the mascot — his face
/// sits beside each answer and the answer is a clean white card (the v2
/// grey bubble read as "system output", not a tutor talking to you).
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.baseUrl,
    this.onStillStuck,
    this.onSetUpByok,
    this.onReact,
    this.onEdit,
    this.onRetry,
  });

  final ChatMessage message;
  final String baseUrl;

  /// Fires when the user taps "still stuck on this?" — see
  /// ChatScreen._markStillStuck's doc comment. Null (and the affordance
  /// hidden) when this message has no `activity` to attach the report to.
  final VoidCallback? onStillStuck;

  /// Passed straight through to BlockView — see its own doc comment.
  final VoidCallback? onSetUpByok;

  /// Sets (or, with null or the same emoji, removes) this message's
  /// reaction. Null hides reactions.
  final void Function(String? emoji)? onReact;

  /// The student's own typed messages: put the text back in the field to
  /// edit and resend. Null when this message can't be edited.
  final VoidCallback? onEdit;

  /// Sage's replies with a 👎 or 😕: "Try a different explanation".
  final VoidCallback? onRetry;

  void _openActions(BuildContext context) {
    final react = onReact;
    if (react == null) return;
    showMessageActions(context, message: message, onReact: react, onEdit: onEdit);
  }

  @override
  Widget build(BuildContext context) {
    if (message.isUser) {
      final theme = Theme.of(context);
      return Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onLongPress: () => _openActions(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
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
                child: Text(
                  message.userText ?? '',
                  style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
                ),
              ),
              if (message.edited || message.reaction != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4, right: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.edited)
                        Text(
                          'edited',
                          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      if (message.reaction != null) ...[
                        const SizedBox(width: 6),
                        _ReactionChip(emoji: message.reaction!, onTap: () => onReact?.call(null)),
                      ],
                    ],
                  ),
                ),
            ],
          ),
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
      child: GestureDetector(
        // Long-press on the bubble's edge or the avatar: inside the text a
        // long-press selects words instead.
        onLongPress: () => _openActions(context),
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
                    if (onReact != null)
                      _ReplyActions(
                        message: message,
                        onReact: onReact!,
                        onRetry: onRetry,
                        onMore: () => _openActions(context),
                      ),
                    if (topic != null) ...[
                      const SizedBox(height: 4),
                      message.struggleMarked
                          ? Text(
                              'Noted — added to History',
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.primary),
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
      ),
    );
  }
}

/// Under each of Sage's replies: copy, react, and — after a 👎 or 😕 —
/// "Try a different explanation".
class _ReplyActions extends StatelessWidget {
  const _ReplyActions({required this.message, required this.onReact, required this.onMore, this.onRetry});

  final ChatMessage message;
  final void Function(String? emoji) onReact;
  final VoidCallback onMore;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 2,
        runSpacing: 4,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.copy_rounded, size: 18, color: muted),
            tooltip: 'Copy',
            onPressed: () => copyMessage(context, message),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.thumb_up_alt_outlined,
              size: 18,
              color: message.reaction == '👍' ? theme.colorScheme.primary : muted,
            ),
            tooltip: 'Helpful',
            onPressed: () => onReact('👍'),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.thumb_down_alt_outlined,
              size: 18,
              color: message.reaction == '👎' ? theme.colorScheme.error : muted,
            ),
            tooltip: 'Not helpful',
            onPressed: () => onReact('👎'),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.add_reaction_outlined, size: 18, color: muted),
            tooltip: 'React',
            onPressed: onMore,
          ),
          if (message.reaction != null && message.reaction != '👍' && message.reaction != '👎')
            _ReactionChip(emoji: message.reaction!, onTap: () => onReact(null)),
          if (onRetry != null && wantsRetry(message.reaction))
            ActionChip(
              avatar: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try a different explanation'),
              onPressed: onRetry,
            ),
        ],
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({required this.emoji, required this.onTap});

  final String emoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: 'Tap to remove',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outline),
          ),
          child: Text(emoji, style: const TextStyle(fontSize: 15)),
        ),
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
