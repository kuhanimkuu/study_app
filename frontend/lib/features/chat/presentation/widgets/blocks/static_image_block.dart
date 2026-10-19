import 'package:flutter/material.dart';

import '../chat_media.dart';

/// Renders a `{"type": "static_image", "content": "/generated/FILENAME.png",
/// "format": "png"}` block — `content` is a URL path server/main.py serves
/// via its "/generated" static mount (see moderator/engine.py's
/// _GENERATED_DIR doc comment for why it's a URL, not a bare filename).
/// Shown from the phone's saved copy when there is one — see ChatMediaStore.
class StaticImageBlockView extends StatelessWidget {
  const StaticImageBlockView({super.key, required this.block, required this.baseUrl});

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
          ChatMediaImage(baseUrl: baseUrl, path: path),
          const ChatMediaConsentPrompt(),
        ],
      ),
    );
  }
}
