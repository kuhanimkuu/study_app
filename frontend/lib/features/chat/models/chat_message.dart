/// A single entry in the chat transcript. `blocks` holds the moderator's
/// raw block list (see server/README.md / json.md's Shape 5) — each block
/// is rendered by BlockView, not modeled as a separate Dart class per
/// type. That keeps this in sync with the server's block vocabulary
/// automatically instead of needing a matching Dart class for every block
/// type the moderator might ever emit.
class ChatMessage {
  ChatMessage.user(this.userText, {this.id, this.reaction, this.edited = false})
      : blocks = null,
        errorText = null,
        activity = null;

  ChatMessage.response(this.blocks, {this.activity, this.id, this.reaction})
      : userText = null,
        errorText = null,
        edited = false;

  ChatMessage.error(this.errorText, {this.id})
      : userText = null,
        blocks = null,
        activity = null,
        edited = false;

  /// LocalDb's row id, once saved — what an edit or a reaction updates.
  int? id;

  /// Mutable since 2026-10-21: the student can edit their own messages.
  String? userText;
  final List<dynamic>? blocks;
  final String? errorText;

  /// An emoji reaction on this message (one per message, like a chat app),
  /// or null. The AI sees reactions on its replies — see [historyFor].
  String? reaction;

  /// The student edited this message after sending it.
  bool edited;

  /// The moderator's suggested activity for this response (topic/engine/
  /// labels — see features/moderator/README.md's output shape). Kept on
  /// the message itself, not just fire-and-forget persisted, so the
  /// "still stuck on this?" affordance can reference it — see
  /// ChatScreen._markStillStuck's doc comment for why that exists.
  final Map<String, dynamic>? activity;

  /// Mutable: flips true once the user taps "still stuck" on this
  /// response, so MessageBubble can show a confirmed state instead of
  /// letting the same response fire duplicate struggle events.
  bool struggleMarked = false;

  bool get isUser => userText != null;
  bool get isError => errorText != null;

  /// A sent attachment shows as "[image: name]" and so on; only typed text
  /// can be edited.
  bool get isEditable => isUser && !_attachmentMarker.hasMatch(userText!);
  static final _attachmentMarker = RegExp(r'^\[(image|pdf|audio|web): ');

  /// The message as plain text — what Copy puts on the clipboard and what
  /// the AI sees in the history. A reply's text and source passages, with
  /// a short label for anything visual.
  String get plainText {
    if (isUser) return userText!;
    if (isError) return errorText!;
    final parts = <String>[];
    for (final block in blocks ?? const []) {
      final b = block as Map;
      final content = b['content']?.toString();
      switch (b['type']) {
        case 'text':
        case 'source':
        case 'clarification':
          final text = (b['type'] == 'clarification' ? b['question'] : content)?.toString();
          if (text != null && text.isNotEmpty) parts.add(text);
        case 'equation':
          parts.add(b['latex']?.toString() ?? '');
        case 'links':
          for (final link in (b['links'] as List? ?? const [])) {
            parts.add('${(link as Map)['label']}: ${link['url']}');
          }
        case 'model_unavailable':
          break;
        default:
          parts.add('[${b['type']}]');
      }
    }
    return parts.where((p) => p.isNotEmpty).join('\n\n');
  }

  /// The recent chat for the server (2026-10-21): the last [maxTurns]
  /// messages before [end], oldest first, with reactions and edits. Errors
  /// are left out — they weren't part of the conversation.
  static List<Map<String, dynamic>> historyFor(List<ChatMessage> messages, {int? end, int maxTurns = 12}) {
    final upTo = end ?? messages.length;
    final turns = <Map<String, dynamic>>[];
    for (final m in messages.take(upTo)) {
      if (m.isError) continue;
      final text = m.plainText.trim();
      if (text.isEmpty) continue;
      turns.add({
        'role': m.isUser ? 'user' : 'assistant',
        'text': text.length > 4000 ? text.substring(0, 4000) : text,
        if (m.reaction != null) 'reaction': m.reaction,
        if (m.edited) 'edited': true,
      });
    }
    return turns.length > maxTurns ? turns.sublist(turns.length - maxTurns) : turns;
  }

  /// Reconstructs a transcript from LocalDb.loadMessages' row shape —
  /// shared by ChatScreen (session switching) and ProjectWorkspaceScreen
  /// (reopening a project's chat tab) so both stay in sync with LocalDb's
  /// stored shape from one place.
  static List<ChatMessage> fromStoredRows(List<Map<String, dynamic>> rows) {
    final messages = <ChatMessage>[];
    for (final row in rows) {
      final id = row['id'] as int?;
      final reaction = row['reaction'] as String?;
      switch (row['role']) {
        case 'user':
          messages.add(ChatMessage.user(row['user_text'] as String? ?? '',
              id: id, reaction: reaction, edited: row['edited'] == true));
        case 'response':
          messages.add(ChatMessage.response(row['blocks'] as List<dynamic>? ?? [], id: id, reaction: reaction));
        case 'error':
          messages.add(ChatMessage.error(row['error_text'] as String? ?? '', id: id));
      }
    }
    return messages;
  }
}
