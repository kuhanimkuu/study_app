import 'package:flutter/material.dart';

/// Prompts for a URL to fetch (the "Web page" attachment option). Returns
/// the entered URL, or null if the user cancelled/left it empty.
Future<String?> showWebUrlDialog(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Fetch a web page'),
      content: TextField(controller: controller, decoration: const InputDecoration(hintText: 'https://...')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Fetch')),
      ],
    ),
  );
}
