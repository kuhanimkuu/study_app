import 'package:flutter/material.dart';

/// The "+" button's bottom sheet — one entry per non-text input mode
/// (Image / PDF / Audio file / Web page). Each callback fires after the
/// sheet closes; ChatScreen owns what actually happens on tap (picking a
/// file, calling the API) — this widget only presents the menu.
Future<void> showAttachmentMenu(
  BuildContext context, {
  required VoidCallback onImage,
  required VoidCallback onPdf,
  required VoidCallback onAudio,
  required VoidCallback onWeb,
}) {
  return showModalBottomSheet(
    context: context,
    builder: (context) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Image'),
            onTap: () {
              Navigator.pop(context);
              onImage();
            },
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('PDF'),
            onTap: () {
              Navigator.pop(context);
              onPdf();
            },
          ),
          ListTile(
            leading: const Icon(Icons.mic_outlined),
            title: const Text('Audio file'),
            onTap: () {
              Navigator.pop(context);
              onAudio();
            },
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('Web page'),
            onTap: () {
              Navigator.pop(context);
              onWeb();
            },
          ),
        ],
      ),
    ),
  );
}
