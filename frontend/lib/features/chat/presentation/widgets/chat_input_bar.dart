import 'package:flutter/material.dart';

/// The bottom input row: attachment "+" button, text field, send button.
/// Purely presentational — ChatScreen owns the controller and the actions
/// the two buttons trigger.
class ChatInputBar extends StatelessWidget {
  const ChatInputBar({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onAttachmentTap,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttachmentTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            IconButton(icon: const Icon(Icons.add), onPressed: onAttachmentTap),
            Expanded(
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(hintText: 'Ask a question...', border: OutlineInputBorder()),
                onSubmitted: (_) => onSend(),
              ),
            ),
            IconButton(icon: const Icon(Icons.send), onPressed: onSend),
          ],
        ),
      ),
    );
  }
}
