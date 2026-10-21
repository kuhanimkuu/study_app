import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/chat_message.dart';

/// The reactions offered on a message. 👎 and 😕 also offer "Try a
/// different explanation" on Sage's replies (see [wantsRetry]).
const reactionEmojis = ['👍', '❤️', '😂', '😮', '🙏', '😕', '👎'];

bool wantsRetry(String? reaction) => reaction == '👎' || reaction == '😕';

Future<void> copyMessage(BuildContext context, ChatMessage message) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  await Clipboard.setData(ClipboardData(text: message.plainText));
  messenger?.showSnackBar(const SnackBar(content: Text('Copied'), duration: Duration(seconds: 2)));
}

/// Long-press menu for a message (2026-10-21): a row of reactions, then
/// Copy, Select text and, for the student's own typed messages, Edit.
Future<void> showMessageActions(
  BuildContext context, {
  required ChatMessage message,
  required void Function(String? emoji) onReact,
  VoidCallback? onEdit,
}) {
  final theme = Theme.of(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final emoji in reactionEmojis)
                  InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      onReact(emoji);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: emoji == message.reaction ? theme.colorScheme.primaryContainer : null,
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 26)),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 20),
          ListTile(
            leading: const Icon(Icons.copy_rounded),
            title: const Text('Copy'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              copyMessage(context, message);
            },
          ),
          ListTile(
            leading: const Icon(Icons.text_fields_rounded),
            title: const Text('Select text'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              showSelectTextDialog(context, message.plainText);
            },
          ),
          if (onEdit != null)
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Edit'),
              subtitle: const Text("Sage will answer the new version"),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onEdit();
              },
            ),
          if (message.reaction != null)
            ListTile(
              leading: const Icon(Icons.close_rounded),
              title: Text('Remove reaction ${message.reaction}'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onReact(null);
              },
            ),
        ],
      ),
    ),
  );
}

/// Lets the student pick out part of a message to copy or share with the
/// phone's own selection handles.
Future<void> showSelectTextDialog(BuildContext context, String text) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Select text'),
      content: SingleChildScrollView(child: SelectableText(text)),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Done')),
      ],
    ),
  );
}
