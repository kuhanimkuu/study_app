import '../../core/storage/local_db.dart';
import 'models/chat_message.dart';

/// Where a conversation's messages are kept. The app uses [LocalDbChatStore];
/// tests use an in-memory one.
abstract class ChatStore {
  Future<int> saveMessage({
    required String sessionId,
    required String role,
    String? userText,
    List<dynamic>? blocks,
    String? errorText,
  });
  Future<void> updateMessage(int id, {String? userText, bool? edited, String? reaction, bool clearReaction = false});
  Future<void> deleteMessagesFrom(String sessionId, int id);
}

class LocalDbChatStore implements ChatStore {
  const LocalDbChatStore();

  @override
  Future<int> saveMessage({
    required String sessionId,
    required String role,
    String? userText,
    List<dynamic>? blocks,
    String? errorText,
  }) =>
      LocalDb.instance.saveMessage(sessionId: sessionId, role: role, userText: userText, blocks: blocks, errorText: errorText);

  @override
  Future<void> updateMessage(int id, {String? userText, bool? edited, String? reaction, bool clearReaction = false}) =>
      LocalDb.instance.updateMessage(id, userText: userText, edited: edited, reaction: reaction, clearReaction: clearReaction);

  @override
  Future<void> deleteMessagesFrom(String sessionId, int id) => LocalDb.instance.deleteMessagesFrom(sessionId, id);
}

/// One chat's messages plus what can be done to them (2026-10-21): send,
/// react, edit a sent message, ask for a different explanation. Shared by
/// the main chat and a subject's chat so both behave the same. Each
/// change is saved to the store; the screen calls setState around these.
class ChatConversation {
  ChatConversation({required this.sessionId, this.store = const LocalDbChatStore()});

  String sessionId;
  final ChatStore store;
  final List<ChatMessage> messages = [];

  void replaceAll(String newSessionId, List<ChatMessage> restored) {
    sessionId = newSessionId;
    messages
      ..clear()
      ..addAll(restored);
  }

  /// The chat so far, for the next question (call before [addUser]).
  List<Map<String, dynamic>> history() => ChatMessage.historyFor(messages);

  Future<ChatMessage> addUser(String text) async {
    final message = ChatMessage.user(text);
    messages.add(message);
    message.id = await store.saveMessage(sessionId: sessionId, role: 'user', userText: text);
    return message;
  }

  Future<ChatMessage> addResponse(List<dynamic> blocks, {Map<String, dynamic>? activity}) async {
    final message = ChatMessage.response(blocks, activity: activity);
    messages.add(message);
    message.id = await store.saveMessage(sessionId: sessionId, role: 'response', blocks: blocks);
    return message;
  }

  Future<ChatMessage> addError(String text) async {
    final message = ChatMessage.error(text);
    messages.add(message);
    message.id = await store.saveMessage(sessionId: sessionId, role: 'error', errorText: text);
    return message;
  }

  /// Sets [emoji] as the message's reaction; the same emoji again (or
  /// null) removes it.
  Future<void> react(ChatMessage message, String? emoji) async {
    final next = (emoji == null || emoji == message.reaction) ? null : emoji;
    message.reaction = next;
    final id = message.id;
    if (id != null) await store.updateMessage(id, reaction: next, clearReaction: next == null);
  }

  /// Replaces a sent message's text and drops everything after it (the old
  /// replies answered the old text). Returns the history to resend it with:
  /// the chat before it.
  Future<List<Map<String, dynamic>>> edit(ChatMessage message, String newText) async {
    final index = messages.indexOf(message);
    if (index < 0) throw StateError('message is not in this conversation');
    message
      ..userText = newText
      ..edited = true;
    await _removeFrom(index + 1);
    final id = message.id;
    if (id != null) await store.updateMessage(id, userText: newText, edited: true);
    return ChatMessage.historyFor(messages, end: index);
  }

  /// "Try a different explanation" for [reply]: removes it (and anything
  /// after it) and returns the question to ask again, with a history that
  /// still includes the old reply and its reaction so the AI knows what
  /// didn't work. Null when the reply doesn't follow a typed question.
  Future<({String question, List<Map<String, dynamic>> history})?> prepareRetry(ChatMessage reply) async {
    final index = messages.indexOf(reply);
    if (index < 1 || !messages[index - 1].isEditable) return null;
    final question = messages[index - 1].userText!;
    final history = ChatMessage.historyFor(messages, end: index + 1);
    await _removeFrom(index);
    return (question: question, history: history);
  }

  /// Whether [reply] can be retried (see [prepareRetry]).
  bool canRetry(ChatMessage reply) {
    final index = messages.indexOf(reply);
    return !reply.isUser && !reply.isError && index >= 1 && messages[index - 1].isEditable;
  }

  Future<void> _removeFrom(int index) async {
    if (index >= messages.length) return;
    final firstId = messages[index].id;
    messages.removeRange(index, messages.length);
    if (firstId != null) await store.deleteMessagesFrom(sessionId, firstId);
  }
}
