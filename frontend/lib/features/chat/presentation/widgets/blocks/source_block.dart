import 'package:flutter/material.dart';

/// Renders a `{"type": "source", "content": "...", "source": "..."}` block
/// — a quoted excerpt (from document_engine/searchable_knowledge's search
/// results, or input_pipeline/web_input's fetched page content via
/// server/main.py's /api/ask/web).
class SourceBlockView extends StatelessWidget {
  const SourceBlockView({super.key, required this.block});

  final Map<String, dynamic> block;

  @override
  Widget build(BuildContext context) {
    final source = block['source']?.toString();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: Theme.of(context).colorScheme.outline, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(block['content']?.toString() ?? '', style: Theme.of(context).textTheme.bodySmall),
          if (source != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(source, style: Theme.of(context).textTheme.labelSmall),
            ),
        ],
      ),
    );
  }
}
