import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../app/theme.dart';

/// Real, on-device speech-to-text (the 2026-09-14 architecture decision —
/// "voice stays client-native", see STUDY_OS_PROGRESS.md — implemented in
/// the UI for the first time 2026-09-19). Shows a listening sheet with a
/// live partial transcript; returns the final recognized text on "Done",
/// or null on cancel/failure. The caller decides what to do with the text
/// (this app inserts it into the chat input for the user to review before
/// sending, never auto-sends a transcription — voice recognition can
/// mishear things, and a study question is worth a glance before it goes
/// to the AI moderator).
Future<String?> showVoiceInputSheet(BuildContext context) async {
  final speech = SpeechToText();
  String? initError;
  final available = await speech.initialize(
    onError: (error) => initError = error.errorMsg,
    onStatus: (_) {},
  );

  if (!available) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            initError != null
                ? 'Speech recognition unavailable: $initError'
                : 'Speech recognition isn\'t available on this device — check microphone permission in Settings.',
          ),
        ),
      );
    }
    return null;
  }

  if (!context.mounted) return null;
  return showModalBottomSheet<String>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) => _VoiceListeningSheet(speech: speech),
  );
}

class _VoiceListeningSheet extends StatefulWidget {
  const _VoiceListeningSheet({required this.speech});

  final SpeechToText speech;

  @override
  State<_VoiceListeningSheet> createState() => _VoiceListeningSheetState();
}

class _VoiceListeningSheetState extends State<_VoiceListeningSheet> {
  String _transcript = '';
  bool _listening = true;

  @override
  void initState() {
    super.initState();
    widget.speech.listen(
      onResult: (result) {
        if (!mounted) return;
        setState(() => _transcript = result.recognizedWords);
      },
      listenOptions: SpeechListenOptions(partialResults: true),
    );
  }

  Future<void> _stop() async {
    await widget.speech.stop();
    if (mounted) setState(() => _listening = false);
  }

  void _done() {
    widget.speech.cancel();
    Navigator.of(context).pop(_transcript.trim().isEmpty ? null : _transcript.trim());
  }

  void _cancel() {
    widget.speech.cancel();
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    widget.speech.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: _listening ? StudyOsColors.brandGradient : null,
                color: _listening ? null : theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _listening ? Icons.mic_rounded : Icons.mic_off_rounded,
                color: _listening ? Colors.white : theme.colorScheme.onSurfaceVariant,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _listening ? 'Listening…' : 'Stopped',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 60),
              child: Text(
                _transcript.isEmpty ? 'Say your question…' : _transcript,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: _transcript.isEmpty ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: _cancel, child: const Text('Cancel')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _listening ? _stop : _done,
                    child: Text(_listening ? 'Stop' : 'Use this text'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
