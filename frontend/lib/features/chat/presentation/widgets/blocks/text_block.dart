import 'package:flutter/material.dart';

/// Renders a `{"type": "text", "content": "...", "source": "..."}` block.
/// Verified against the moderator's actual output (features/moderator/
/// engine.py) via real HTTP calls, not assumed from json.md alone.
class TextBlockView extends StatelessWidget {
  const TextBlockView({super.key, required this.block});

  final Map<String, dynamic> block;

  @override
  Widget build(BuildContext context) {
    final source = block['source'] as String?;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(block['content']?.toString() ?? ''),
          if (source != null && source != 'moderator')
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('— $source', style: Theme.of(context).textTheme.labelSmall),
            ),
        ],
      ),
    );
  }
}
