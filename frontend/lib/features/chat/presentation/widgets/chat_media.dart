import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/storage/chat_media_store.dart';

/// How long the server keeps chat media — server/workers/cleanup.py's
/// GENERATED_RETENTION_DAYS default. Only used in wording shown to students.
const chatMediaServerRetention = 'about two weeks';

/// A chat picture or animation: the copy saved on this phone when there is
/// one (or once the student has agreed to saving), else straight from the
/// server as before.
class ChatMediaImage extends StatefulWidget {
  const ChatMediaImage({super.key, required this.baseUrl, required this.path, this.kind = 'picture'});

  final String baseUrl;
  final String path;

  /// "picture" or "animation" — wording for the expired message.
  final String kind;

  @override
  State<ChatMediaImage> createState() => _ChatMediaImageState();
}

class _ChatMediaImageState extends State<ChatMediaImage> {
  final _store = ChatMediaStore.instance;

  /// Only while saving a copy right now (the student agreed to saving and
  /// this one isn't saved yet); otherwise the build needs no waiting.
  Future<String?>? _saving;

  @override
  void initState() {
    super.initState();
    _startSavingIfAgreed();
    _store.consent.addListener(_onConsentChanged);
  }

  @override
  void dispose() {
    _store.consent.removeListener(_onConsentChanged);
    super.dispose();
  }

  void _startSavingIfAgreed() {
    if (_store.consent.value == ChatMediaConsent.save && _store.savedPath(widget.path) == null) {
      _saving = _store.pathFor(widget.baseUrl, widget.path);
    }
  }

  void _onConsentChanged() {
    // just agreed to saving: keep this one too while it's still on the server
    if (mounted) setState(_startSavingIfAgreed);
  }

  Widget _unavailable(BuildContext context, Object error, StackTrace? stackTrace) =>
      ChatMediaUnavailable(kind: widget.kind);

  Widget _fromServer() =>
      Image.network('${widget.baseUrl}${widget.path}', gaplessPlayback: true, errorBuilder: _unavailable);

  @override
  Widget build(BuildContext context) {
    final saved = _store.savedPath(widget.path);
    if (saved != null) return _store.localImage(saved, errorBuilder: _unavailable);
    final saving = _saving;
    if (saving == null) return _fromServer();
    return FutureBuilder<String?>(
      future: saving,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
        }
        final local = snapshot.data;
        return local != null ? _store.localImage(local, errorBuilder: _unavailable) : _fromServer();
      },
    );
  }
}

/// Shown where a chat picture/file used to be once the server has deleted
/// it and no copy was saved on the phone.
class ChatMediaUnavailable extends StatelessWidget {
  const ChatMediaUnavailable({super.key, this.kind = 'picture'});

  final String kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = ChatMediaStore.supported && ChatMediaStore.instance.consent.value != ChatMediaConsent.save
        ? ' To keep new ones, turn on "Chat files on this phone" in Profile.'
        : '';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.hide_image_outlined, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This $kind is no longer available. Chat files stay on the server for $chatMediaServerRetention.$hint',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens a chat PDF or 3D model: the saved copy if there is one (saving it
/// first when the student agreed), otherwise the server link in the
/// phone's browser, as before.
Future<void> openChatMediaFile(BuildContext context, String baseUrl, String path, String what) async {
  final messenger = ScaffoldMessenger.of(context);
  final store = ChatMediaStore.instance;
  try {
    final local = await store.pathFor(baseUrl, path);
    if (local != null && await store.openLocal(local)) return;
    final uri = Uri.parse('$baseUrl$path');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      messenger.showSnackBar(SnackBar(content: Text('Could not open $uri')));
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not open $what: $e')));
  }
}

/// The one-time question under the first chat picture/file: save chat
/// media on this phone or not. Explains the trade-off (old chats keep
/// their pictures vs. phone storage) so nothing is stored without the
/// student knowing. Only one is shown at a time, and none once answered;
/// the answer can be changed in Profile.
class ChatMediaConsentPrompt extends StatefulWidget {
  const ChatMediaConsentPrompt({super.key});

  @override
  State<ChatMediaConsentPrompt> createState() => _ChatMediaConsentPromptState();
}

class _ChatMediaConsentPromptState extends State<ChatMediaConsentPrompt> {
  // Several pictures can be on screen at once — only the first prompt to
  // build shows; the rest render nothing.
  static Object? _shownBy;

  @override
  void dispose() {
    if (identical(_shownBy, this)) _shownBy = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ChatMediaStore.supported) return const SizedBox.shrink();
    return ValueListenableBuilder<ChatMediaConsent>(
      valueListenable: ChatMediaStore.instance.consent,
      builder: (context, consent, _) {
        if (consent != ChatMediaConsent.undecided) return const SizedBox.shrink();
        _shownBy ??= this;
        if (!identical(_shownBy, this)) return const SizedBox.shrink();

        final theme = Theme.of(context);
        return Card(
          margin: const EdgeInsets.only(top: 8, bottom: 4),
          color: theme.colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.save_alt_rounded, size: 20, color: theme.colorScheme.onSecondaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Save chat pictures and PDFs on this phone?',
                        style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSecondaryContainer),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Charts, pictures and PDFs from your chats are kept on our server for $chatMediaServerRetention, '
                  'then deleted. If you save them on this phone, old chats keep them, but they use your '
                  "phone's storage (usually well under 1 MB each). You can change this or delete them any "
                  'time in Profile → Chat files on this phone.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSecondaryContainer),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => ChatMediaStore.instance.setConsent(ChatMediaConsent.dontSave),
                      child: const Text("Don't save"),
                    ),
                    const SizedBox(width: 4),
                    FilledButton.tonal(
                      onPressed: () => ChatMediaStore.instance.setConsent(ChatMediaConsent.save),
                      child: const Text('Save on this phone'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A chat PDF or 3D model as a card with an Open action. When the student
/// agreed to saving, the file is saved as soon as the card appears — not
/// only when opened — so it's kept before the server deletes it.
class ChatMediaFileCard extends StatefulWidget {
  const ChatMediaFileCard({
    super.key,
    required this.baseUrl,
    required this.path,
    required this.icon,
    required this.title,
    required this.what,
  });

  final String baseUrl;
  final String path;
  final IconData icon;
  final String title;

  /// e.g. "PDF" — used in error messages.
  final String what;

  @override
  State<ChatMediaFileCard> createState() => _ChatMediaFileCardState();
}

class _ChatMediaFileCardState extends State<ChatMediaFileCard> {
  final _store = ChatMediaStore.instance;
  late String? _local = _store.savedPath(widget.path);

  @override
  void initState() {
    super.initState();
    _refresh();
    _store.consent.addListener(_refresh);
  }

  @override
  void dispose() {
    _store.consent.removeListener(_refresh);
    super.dispose();
  }

  /// Saves the file now if the student agreed to saving (a no-op otherwise).
  Future<void> _refresh() async {
    if (_local != null || _store.consent.value != ChatMediaConsent.save) return;
    final local = await _store.pathFor(widget.baseUrl, widget.path);
    if (mounted && local != _local) setState(() => _local = local);
  }

  Future<void> _open() async {
    await openChatMediaFile(context, widget.baseUrl, widget.path, widget.what);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: Icon(widget.icon),
            title: Text(widget.title),
            subtitle: Text(
              _local != null ? 'Saved on this phone' : '${widget.baseUrl}${widget.path}',
              style: theme.textTheme.bodySmall,
            ),
            trailing: IconButton(icon: const Icon(Icons.open_in_new), tooltip: 'Open', onPressed: _open),
            onTap: _open,
          ),
        ),
        const ChatMediaConsentPrompt(),
      ],
    );
  }
}
