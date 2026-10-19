import 'package:flutter/material.dart';

import '../chat_media.dart';

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
///
/// Since 2026-10-19 the card opens the copy saved on this phone when the
/// student chose to keep chat files (ChatMediaFileCard / ChatMediaStore) —
/// the server deletes them after about two weeks.
class PdfBlockView extends StatelessWidget {
  const PdfBlockView({super.key, required this.block, required this.baseUrl});

  final Map<String, dynamic> block;
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    final docType = block['doc_type']?.toString() ?? 'document';
    return ChatMediaFileCard(
      baseUrl: baseUrl,
      path: block['content']?.toString() ?? '',
      icon: Icons.picture_as_pdf_outlined,
      title: 'Generated $docType (PDF)',
      what: 'PDF',
    );
  }
}
