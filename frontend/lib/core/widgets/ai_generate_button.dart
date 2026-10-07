import 'package:flutter/material.dart';

import '../api/api_client.dart';

/// "Generate with AI" — one shared button for every generate-from-material
/// action (concepts, flashcards, practice questions; 2026-10-07).
///
/// [onGenerate] does the API call and returns the success message to show
/// (e.g. "Added 6 concepts"); any ApiException's own message is shown
/// as-is, since the server's 503/502/400 details are already actionable
/// ("add your own API key…", "this project has no material yet…").
/// Generation takes seconds on a BYOK model but can take minutes on the
/// free local one, so the busy state says so instead of just spinning.
class AiGenerateButton extends StatefulWidget {
  const AiGenerateButton({
    super.key,
    required this.label,
    required this.onGenerate,
    this.onDone,
    this.expand = false,
  });

  final String label;
  final Future<String> Function() onGenerate;

  /// Called after a successful generation, e.g. to reload the list.
  final VoidCallback? onDone;

  /// Full-width (empty states) vs. intrinsic width (list headers).
  final bool expand;

  @override
  State<AiGenerateButton> createState() => _AiGenerateButtonState();
}

class _AiGenerateButtonState extends State<AiGenerateButton> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await widget.onGenerate();
      messenger.showSnackBar(SnackBar(content: Text(message)));
      widget.onDone?.call();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), duration: const Duration(seconds: 6)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Generation failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final button = FilledButton.tonalIcon(
      onPressed: _busy ? null : _run,
      icon: _busy
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.auto_awesome),
      label: Text(_busy ? 'Generating… this can take a minute' : widget.label),
    );
    return widget.expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// "Added 3 flashcards" / "Added 1 concept (2 were already there)".
String generatedSummary(Map<String, dynamic> result, String listKey, String singular) {
  final added = (result[listKey] as List<dynamic>? ?? const []).length;
  final skipped = (result['skipped_existing'] as num?)?.toInt() ?? 0;
  final noun = added == 1 ? singular : '${singular}s';
  if (added == 0) {
    return skipped > 0 ? 'Nothing new — all $skipped already existed.' : 'Nothing new was generated.';
  }
  return 'Added $added $noun${skipped > 0 ? ' ($skipped already existed)' : ''}.';
}
