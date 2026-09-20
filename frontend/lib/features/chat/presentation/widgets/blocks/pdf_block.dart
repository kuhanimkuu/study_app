import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Renders a `{"type": "pdf", "content": "/generated/FILENAME.pdf",
/// "doc_type": "study_guide"}` block (from document_generation/
/// generate_docs, or math_engine/graphing's PDF export) as a reference
/// card with a real "Open" action — not an inline PDF preview (that
/// still needs a dedicated viewer package, e.g. syncfusion_flutter_pdfviewer,
/// not added to this project), but genuinely openable: launches the
/// file's URL in the device's own browser, which has its own built-in
/// PDF viewer and download button. This works over the same `adb
/// reverse` tunnel used for real-device dev testing (see
/// server/README.md) since that tunnel forwards 127.0.0.1 for the whole
/// device, not just this one app.
///
/// Real bug fixed here: this used to be plain, non-interactive text
/// telling the user the file was "downloadable" with no way to actually
/// open or download it — found via real device testing.
class PdfBlockView extends StatelessWidget {
  const PdfBlockView({super.key, required this.block, required this.baseUrl});

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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open PDF: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = block['content']?.toString() ?? '';
    final docType = block['doc_type']?.toString() ?? 'document';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.picture_as_pdf_outlined),
        title: Text('Generated $docType (PDF)'),
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
