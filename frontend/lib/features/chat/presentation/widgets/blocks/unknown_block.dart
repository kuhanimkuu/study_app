import 'package:flutter/material.dart';

/// Fallback for any block type without a real renderer yet — shows the
/// type and raw content instead of silently dropping it. json.md's full
/// block vocabulary (text, equation, interactive_graph, diagram, animation,
/// 3d, video, pdf, quiz, table, source + clarification/error) is bigger
/// than what has a real widget today; an unrendered block should be
/// visibly "not implemented", not invisible. See block_view.dart's doc
/// comment for exactly which types currently have real widgets.
class UnknownBlockView extends StatelessWidget {
  const UnknownBlockView({super.key, required this.block});

  final Map<String, dynamic> block;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(6)),
      child: Text(
        'Block type "${block['type']}" isn\'t rendered yet:\n$block',
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
      ),
    );
  }
}
