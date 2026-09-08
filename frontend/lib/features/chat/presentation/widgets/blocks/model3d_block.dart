import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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

  Future<void> _open(BuildContext context) async {
    final path = block['content']?.toString() ?? '';
    final uri = Uri.parse('$baseUrl$path');
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open $uri')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open 3D model: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = block['content']?.toString() ?? '';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.view_in_ar_outlined),
        title: Text('3D model generated (${block['format'] ?? 'glb'})'),
        subtitle: Text('$baseUrl$path', style: Theme.of(context).textTheme.bodySmall),
        trailing: IconButton(
          icon: const Icon(Icons.open_in_new),
          tooltip: 'Open',
          onPressed: () => _open(context),
        ),
        onTap: () => _open(context),
      ),
    );
  }
}
