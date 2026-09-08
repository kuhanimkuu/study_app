import 'package:flutter/material.dart';

/// Renders a `{"type": "clarification", "question": "..."}` block — the
/// moderator asking the user something before it can proceed (json.md
/// §6's clarification loop). The chat screen's own state (see
/// _pendingPdfName in chat_screen.dart) decides how the *next* message
/// gets routed after one of these appears; this widget only displays it.
class ClarificationBlockView extends StatelessWidget {
  const ClarificationBlockView({super.key, required this.block});

  final Map<String, dynamic> block;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.help_outline, size: 18, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(child: Text(block['question']?.toString() ?? '')),
        ],
      ),
    );
  }
}
