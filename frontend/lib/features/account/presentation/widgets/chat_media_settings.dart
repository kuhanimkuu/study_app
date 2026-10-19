import 'package:flutter/material.dart';

import '../../../../core/storage/chat_media_store.dart';
import '../../../chat/presentation/widgets/chat_media.dart';

/// Profile → "Chat files on this phone": the same choice the chat asks
/// once (ChatMediaConsentPrompt), plus how much space saved files use and
/// a way to delete them — so the student always knows, and controls, what
/// the app keeps on their phone.
class ChatMediaSettingsCard extends StatefulWidget {
  const ChatMediaSettingsCard({super.key});

  @override
  State<ChatMediaSettingsCard> createState() => _ChatMediaSettingsCardState();
}

class _ChatMediaSettingsCardState extends State<ChatMediaSettingsCard> {
  final _store = ChatMediaStore.instance;
  int? _bytes;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _loadUsage();
  }

  Future<void> _loadUsage() async {
    final bytes = await _store.usedBytes();
    if (mounted) setState(() => _bytes = bytes);
  }

  String _size(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete saved chat files?'),
        content: Text(
          'This frees ${_size(_bytes ?? 0)} on this phone. Old chats will show their pictures and PDFs '
          'only while they are still on the server ($chatMediaServerRetention after they were made).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _clearing = true);
    await _store.clear();
    if (!mounted) return;
    setState(() => _clearing = false);
    await _loadUsage();
  }

  @override
  Widget build(BuildContext context) {
    if (!ChatMediaStore.supported) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 10),
        child: ValueListenableBuilder<ChatMediaConsent>(
          valueListenable: _store.consent,
          builder: (context, consent, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.save_alt_rounded, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Chat files on this phone',
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                  Switch(
                    value: consent == ChatMediaConsent.save,
                    onChanged: (on) => _store.setConsent(on ? ChatMediaConsent.save : ChatMediaConsent.dontSave),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 32, right: 8),
                child: Text(
                  consent == ChatMediaConsent.save
                      ? 'Charts, pictures and PDFs from your chats are saved here, so old chats keep them after '
                          'the server deletes its copy ($chatMediaServerRetention).'
                      : 'Off: chat pictures and PDFs load from the server and disappear from old chats after '
                          '$chatMediaServerRetention. Nothing is saved on this phone.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 32, top: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _bytes == null ? 'Checking space used…' : 'Using ${_size(_bytes!)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    TextButton(
                      onPressed: (_bytes ?? 0) == 0 || _clearing ? null : _confirmClear,
                      child: Text(_clearing ? 'Deleting…' : 'Delete saved files'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
