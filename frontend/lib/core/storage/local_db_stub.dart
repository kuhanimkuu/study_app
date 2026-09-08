/// Web build's stand-in for local_db_io.dart — see local_db.dart's doc
/// comment. Nothing here survives a page reload; this project's
/// local-first design targets Android/Windows, so that's an honest
/// limitation rather than a bug to route around.
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  final List<Map<String, dynamic>> _messages = [];
  final List<Map<String, dynamic>> _events = [];

  Future<void> open(int userId) async {}

  Future<void> close() async {
    _messages.clear();
    _events.clear();
  }

  Future<void> saveMessage({
    required String sessionId,
    required String role,
    String? userText,
    List<dynamic>? blocks,
    String? errorText,
  }) async {
    _messages.add({
      'session_id': sessionId,
      'role': role,
      'user_text': userText,
      'blocks': blocks,
      'error_text': errorText,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> loadMessages({String? sessionId}) async {
    if (sessionId == null) return List.of(_messages);
    return _messages.where((m) => m['session_id'] == sessionId).toList();
  }

  Future<List<Map<String, dynamic>>> loadSessions() async {
    final bySession = <String, List<Map<String, dynamic>>>{};
    for (final m in _messages) {
      final sessionId = m['session_id'] as String;
      if (sessionId.startsWith('project_')) continue;
      (bySession[sessionId] ??= []).add(m);
    }
    final sessions = bySession.entries.map((entry) {
      final msgs = entry.value;
      final firstUser = msgs.firstWhere(
        (m) => m['role'] == 'user',
        orElse: () => const {},
      );
      return {
        'session_id': entry.key,
        'last_activity': msgs.last['created_at'] as String,
        'preview': firstUser['user_text'] as String?,
      };
    }).toList();
    sessions.sort((a, b) => (b['last_activity'] as String).compareTo(a['last_activity'] as String));
    return sessions;
  }

  Future<void> deleteSession(String sessionId) async {
    _messages.removeWhere((m) => m['session_id'] == sessionId);
  }

  Future<void> saveActivity({
    String? topic,
    double? score,
    required List<String> labels,
    String? event,
    String? engine,
    required String timestamp,
  }) async {
    _events.add({
      'topic': topic,
      'score': score,
      'labels': labels,
      'event': event,
      'engine': engine,
      'timestamp': timestamp,
    });
  }

  Future<List<Map<String, dynamic>>> loadActivityForQuery() async {
    return List.of(_events);
  }
}
