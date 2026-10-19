import 'package:flutter/material.dart';

import '../chat_media.dart';

/// Renders a `{"type": "animation", "content": "/generated/FILENAME.gif",
/// "fps": 2}` block. Flutter's Image widget plays animated GIFs natively —
/// no extra package needed for this one.
class AnimationBlockView extends StatelessWidget {
  const AnimationBlockView({super.key, required this.block, required this.baseUrl});

  final Map<String, dynamic> block;
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    final path = block['content']?.toString();
    if (path == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChatMediaImage(baseUrl: baseUrl, path: path, kind: 'animation'),
          const ChatMediaConsentPrompt(),
        ],
      ),
    );
  }
}
