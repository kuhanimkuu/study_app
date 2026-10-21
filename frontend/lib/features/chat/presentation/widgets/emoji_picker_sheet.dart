import 'package:flutter/material.dart';

/// A small built-in emoji picker for the chat field (2026-10-21) — the
/// phone keyboard's own emoji key works too; this is quicker to find and
/// needs no extra package.
const emojiGroups = {
  'Smileys': ['😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣', '😊', '🙂', '😉', '😍', '🥰', '😘', '😎', '🤓', '🧐', '🤔', '🤨', '😐', '😑', '😶', '🙄', '😏', '😴', '😪', '😮', '😯', '😲', '😳', '🥺', '😢', '😭', '😤', '😠', '😡', '🤯', '😱', '🥳', '😇', '🤗', '🤭', '🫡', '😬', '😓', '😩', '😫', '🥱'],
  'Hands': ['👍', '👎', '👏', '🙌', '🙏', '🤝', '👌', '✌️', '🤞', '👋', '💪', '✍️', '👀', '🫶', '☝️', '👆', '👇', '👉', '👈', '🤙'],
  'Study': ['📚', '📖', '📝', '✏️', '🖊️', '📐', '📏', '🧮', '🔬', '🧪', '🧬', '🧠', '💡', '🎓', '🏫', '📅', '⏰', '⌛', '✅', '❌', '❓', '❗', '💯', '🔥', '⭐', '🏆', '🎯', '📊', '📈', '💻'],
  'Hearts': ['❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '💔', '💕', '💖', '✨', '🎉', '🎊', '🌟', '☀️', '🌈', '☕', '🍕', '🎵'],
};

Future<String?> showEmojiPicker(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SizedBox(
        height: MediaQuery.of(sheetContext).size.height * 0.45,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            for (final group in emojiGroups.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                child: Text(group.key, style: Theme.of(sheetContext).textTheme.labelMedium),
              ),
              Wrap(
                children: [
                  for (final emoji in group.value)
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => Navigator.of(sheetContext).pop(emoji),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(emoji, style: const TextStyle(fontSize: 28)),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Puts [text] at the cursor (replacing any selection) and leaves the
/// cursor after it.
void insertAtCursor(TextEditingController controller, String text) {
  final value = controller.value;
  final selection = value.selection.isValid ? value.selection : TextSelection.collapsed(offset: value.text.length);
  final newText = value.text.replaceRange(selection.start, selection.end, text);
  controller.value = TextEditingValue(
    text: newText,
    selection: TextSelection.collapsed(offset: selection.start + text.length),
  );
}
