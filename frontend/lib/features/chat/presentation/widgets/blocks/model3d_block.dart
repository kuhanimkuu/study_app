import 'package:flutter/material.dart';

import '../chat_media.dart';

/// Renders a `{"type": "3d", "content": "/generated/FILENAME.glb", "format":
/// "glb"}` block as a reference card, NOT inline 3D rendering — actual glTF/
/// GLB viewing needs a dedicated package (e.g. model_viewer_plus, WebView-
/// based) not added to this project. The "Open" action launches the file
/// externally (same mechanism as PdfBlockView) — for a browser that has no
/// GLB viewer this typically just downloads the file rather than
/// rendering it, which is still strictly better than the old fully-inert
/// text-only card, and a real GLB viewer can later point at the exact
/// same URL.
class Model3dBlockView extends StatelessWidget {
  const Model3dBlockView({super.key, required this.block, required this.baseUrl});

  final Map<String, dynamic> block;
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    return ChatMediaFileCard(
      baseUrl: baseUrl,
      path: block['content']?.toString() ?? '',
      icon: Icons.view_in_ar_outlined,
      title: '3D model generated (${block['format'] ?? 'glb'})',
      what: '3D model',
    );
  }
}
