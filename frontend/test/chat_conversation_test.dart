// Chat editing, reactions and "try a different explanation" (2026-10-21):
// what the conversation keeps, what it deletes, and the history the AI is
// sent each time.

import 'package:flutter_test/flutter_test.dart';

import 'package:study_os_frontend/features/chat/chat_conversation.dart';
import 'package:study_os_frontend/features/chat/models/chat_message.dart';

class _MemoryStore implements ChatStore {
  final rows = <int, Map<String, dynamic>>{};
  var _next = 1;

  @override
  Future<int> saveMessage({required String sessionId, required String role, String? userText, List<dynamic>? blocks, String? errorText}) async {
    final id = _next++;
    rows[id] = {'session': sessionId, 'role': role, 'text': userText};
    return id;
  }

  @override
  Future<void> updateMessage(int id, {String? userText, bool? edited, String? reaction, bool clearReaction = false}) async {
    final row = rows[id]!;
    if (userText != null) row['text'] = userText;
    if (edited != null) row['edited'] = edited;
    if (reaction != null || clearReaction) row['reaction'] = reaction;
  }

  @override
  Future<void> deleteMessagesFrom(String sessionId, int id) async =>
      rows.removeWhere((key, row) => row['session'] == sessionId && key >= id);
}

List<dynamic> _reply(String text) => [
      {'type': 'text', 'content': text, 'source': 'moderator'},
    ];

Future<ChatConversation> _chat(_MemoryStore store) async {
  final chat = ChatConversation(sessionId: 's', store: store);
  await chat.addUser('what is osmosis');
  await chat.addResponse(_reply('Water moving across a membrane.'));
  await chat.addUser('and diffusion?');
  await chat.addResponse(_reply('Particles spreading out.'));
  return chat;
}

void main() {
  test('history carries the chat, reactions and edits, oldest first', () async {
    final chat = await _chat(_MemoryStore());
    await chat.react(chat.messages[1], '👎');
    final history = chat.history();
    expect(history.map((t) => t['role']), ['user', 'assistant', 'user', 'assistant']);
    expect(history[1], {'role': 'assistant', 'text': 'Water moving across a membrane.', 'reaction': '👎'});
  });

  test('editing a message drops the replies after it and resends with the chat before it', () async {
    final store = _MemoryStore();
    final chat = await _chat(store);
    final history = await chat.edit(chat.messages[0], 'what is osmosis in plants');

    expect(chat.messages, hasLength(1));
    expect(chat.messages.single.userText, 'what is osmosis in plants');
    expect(chat.messages.single.edited, isTrue);
    expect(history, isEmpty); // nothing came before the first message
    expect(store.rows.keys, [1]); // the old replies are gone from the phone too
    expect(store.rows[1]!['text'], 'what is osmosis in plants');
  });

  test('editing a later message keeps what came before it', () async {
    final chat = await _chat(_MemoryStore());
    final history = await chat.edit(chat.messages[2], 'and active transport?');
    expect(chat.messages, hasLength(3));
    expect(history.map((t) => t['text']), ['what is osmosis', 'Water moving across a membrane.']);
  });

  test('try again replaces the reply, and the AI sees what missed', () async {
    final chat = await _chat(_MemoryStore());
    final reply = chat.messages[3];
    await chat.react(reply, '😕');
    expect(chat.canRetry(reply), isTrue);

    final retry = await chat.prepareRetry(reply);
    expect(retry!.question, 'and diffusion?');
    expect(retry.history.last, {'role': 'assistant', 'text': 'Particles spreading out.', 'reaction': '😕'});
    expect(chat.messages, hasLength(3)); // the old reply is gone; the new one will take its place
  });

  test('the same reaction twice removes it', () async {
    final store = _MemoryStore();
    final chat = await _chat(store);
    await chat.react(chat.messages[1], '❤️');
    expect(store.rows[2]!['reaction'], '❤️');
    await chat.react(chat.messages[1], '❤️');
    expect(chat.messages[1].reaction, isNull);
    expect(store.rows[2]!['reaction'], isNull);
  });

  test('attachments and errors are not editable or retryable', () async {
    final chat = ChatConversation(sessionId: 's', store: _MemoryStore());
    await chat.addUser('[pdf: notes.pdf]');
    await chat.addResponse(_reply('Which part?'));
    await chat.addError('timed out');
    expect(chat.messages[0].isEditable, isFalse);
    expect(chat.canRetry(chat.messages[1]), isFalse);
    expect(chat.history().map((t) => t['role']), ['user', 'assistant']); // errors left out
  });

  test('plain text of a reply, for copying', () {
    final reply = ChatMessage.response([
      {'type': 'text', 'content': 'Mitosis has four phases.'},
      {'type': 'diagram', 'kind': 'process'},
      {
        'type': 'links',
        'links': [
          {'label': 'Wikipedia: mitosis', 'url': 'https://en.wikipedia.org/w/index.php?search=mitosis'},
        ],
      },
    ]);
    expect(
      reply.plainText,
      'Mitosis has four phases.\n\n[diagram]\n\nWikipedia: mitosis: https://en.wikipedia.org/w/index.php?search=mitosis',
    );
  });
}
