import 'package:flutter/material.dart';

/// Renders a `{"type": "error", "engine": "...", "message": "..."}` block
/// — an engine failure the moderator caught and surfaced honestly (json.md
/// Shape 4b) instead of crashing the whole response.
class ErrorBlockView extends StatelessWidget {
  const ErrorBlockView({super.key, required this.block});

  final Map<String, dynamic> block;

  @override
  Widget build(BuildContext context) {
    final engine = block['engine']?.toString();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${engine != null ? '$engine: ' : ''}${block['message'] ?? 'unknown error'}'),
          ),
        ],
      ),
    );
  }
}
