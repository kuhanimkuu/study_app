/// A single entry in the chat transcript. `blocks` holds the moderator's
/// raw block list (see server/README.md / json.md's Shape 5) — each block
/// is rendered by BlockView, not modeled as a separate Dart class per
/// type. That keeps this in sync with the server's block vocabulary
/// automatically instead of needing a matching Dart class for every block
/// type the moderator might ever emit.
class ChatMessage {
  ChatMessage.user(this.userText)
      : blocks = null,
        errorText = null,
        activity = null;

  ChatMessage.response(this.blocks, {this.activity})
      : userText = null,
        errorText = null;

  ChatMessage.error(this.errorText)
      : userText = null,
        blocks = null,
        activity = null;

  final String? userText;
  final List<dynamic>? blocks;
  final String? errorText;

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

  /// Reconstructs a transcript from LocalDb.loadMessages' row shape —
  /// shared by ChatScreen (session switching) and ProjectWorkspaceScreen
  /// (reopening a project's chat tab) so both stay in sync with LocalDb's
  /// stored shape from one place.
  static List<ChatMessage> fromStoredRows(List<Map<String, dynamic>> rows) {
    final messages = <ChatMessage>[];
    for (final row in rows) {
      switch (row['role']) {
        case 'user':
          messages.add(ChatMessage.user(row['user_text'] as String? ?? ''));
        case 'response':
          messages.add(ChatMessage.response(row['blocks'] as List<dynamic>? ?? []));
        case 'error':
          messages.add(ChatMessage.error(row['error_text'] as String? ?? ''));
      }
    }
    return messages;
  }
}
