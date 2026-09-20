import 'package:flutter/material.dart';

/// Shown above the input bar while a typed message would be routed as a
/// query against an uploaded PDF instead of a fresh question — see
/// chat_screen.dart's _pendingPdfName doc comment for the full flow this
/// is the visible half of. Dismissible so the user can break out of
/// "PDF query mode" back to normal chat without sending another message.
class PendingPdfChip extends StatelessWidget {
  const PendingPdfChip({super.key, required this.filename, required this.onDismiss});

  final String filename;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Chip(label: Text('Asking about: $filename'), onDeleted: onDismiss),
      ),
    );
  }
}
