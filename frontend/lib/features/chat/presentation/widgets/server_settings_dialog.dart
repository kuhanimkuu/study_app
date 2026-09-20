import 'package:flutter/material.dart';

/// Lets the user view/edit the server base URL — the app has no way to
/// guess this correctly on its own (see chat_screen.dart's _defaultBaseUrl
/// doc comment: Android emulator vs. a real device vs. desktop/web all
/// need different values), so this dialog is the escape hatch. Returns
/// the new URL, or null if the user cancelled/left it unchanged.
Future<String?> showServerSettingsDialog(BuildContext context, String currentUrl) {
  final controller = TextEditingController(text: currentUrl);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Server URL'),
      content: TextField(controller: controller),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
      ],
    ),
  );
}
