import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

/// The bottom input row: attachment "+" button, a pill-shaped text field,
/// and a circular send button that fills with the brand gradient once
/// there's something to send. Purely presentational — ChatScreen owns
/// the controller and the actions the two buttons trigger.
class ChatInputBar extends StatefulWidget {
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
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.trim().isNotEmpty;
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              icon: Icon(Icons.add_circle_outline, color: theme.colorScheme.onSurfaceVariant),
              onPressed: widget.onAttachmentTap,
            ),
            Expanded(
              child: TextField(
                controller: widget.controller,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Ask a question...',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                ),
                onSubmitted: (_) => widget.onSend(),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                gradient: hasText ? StudyOsColors.brandGradient : null,
                color: hasText ? null : theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(Icons.arrow_upward_rounded, color: hasText ? Colors.white : theme.colorScheme.onSurfaceVariant),
                onPressed: hasText ? widget.onSend : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
