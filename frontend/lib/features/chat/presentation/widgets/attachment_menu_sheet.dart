import 'package:flutter/material.dart';

/// The "+" button's bottom sheet — one entry per non-text input mode
/// (Camera / Photo library / PDF / Audio file / Web page). Each callback
/// fires after the sheet closes; ChatScreen owns what actually happens on
/// tap (picking a file, calling the API) — this widget only presents the
/// menu. Camera and Photo library are separate entries (not one "Image"
/// entry that opens a second picker) so the common case — snap a photo of
/// a textbook page — is one tap, not two.
Future<void> showAttachmentMenu(
  BuildContext context, {
  required VoidCallback onCamera,
  required VoidCallback onImage,
  required VoidCallback onPdf,
  required VoidCallback onAudio,
  required VoidCallback onWeb,
}) {
  return showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.outline, borderRadius: BorderRadius.circular(2)),
            ),
            _AttachmentTile(icon: Icons.camera_alt_outlined, label: 'Take photo', onTap: onCamera),
            _AttachmentTile(icon: Icons.image_outlined, label: 'Photo library', onTap: onImage),
            _AttachmentTile(icon: Icons.picture_as_pdf_outlined, label: 'PDF', onTap: onPdf),
            _AttachmentTile(icon: Icons.mic_outlined, label: 'Audio file', onTap: onAudio),
            _AttachmentTile(icon: Icons.link, label: 'Web page', onTap: onWeb),
          ],
        ),
      ),
    ),
  );
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: theme.colorScheme.primary),
      ),
      title: Text(label),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }
}
