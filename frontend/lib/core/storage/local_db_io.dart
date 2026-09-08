import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// On-device store for chat history and activity/progress events — the two
/// things the local-first pivot moved OFF the server (see
/// server/main.py's architecture note: the server keeps only auth + a
/// per-user encryption key, this device is the source of truth for
/// everything else). One database file per user_id, so switching accounts
/// on the same install never mixes or leaks one user's data into another's.
///
/// `loadActivityForQuery()`'s return shape matches
/// personalization/query_memory/engine.py's `events` input exactly, so it
/// can be sent straight through as `local_events` on an /api/ask/text call
/// — see routers/ask.py's TextAsk.local_events and ChatScreen's memory
/// query wiring.
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  Database? _db;
  int? _userId;

  Future<void> open(int userId) async {
    if (_db != null && _userId == userId) return;
    await close();
    _userId = userId;

    if (!Platform.isAndroid && !Platform.isIOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'study_os_user_$userId.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE chat_messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            role TEXT NOT NULL,
            user_text TEXT,
            blocks_json TEXT,
            error_text TEXT,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE activity_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            topic TEXT,
            score REAL,
            labels_json TEXT NOT NULL,
            event TEXT,
            engine TEXT,
            timestamp TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _userId = null;
  }

  Database get _requireDb {
    final db = _db;
    if (db == null) throw StateError('LocalDb.open(userId) must be called before use');
    return db;
  }

  Future<void> saveMessage({
    required String sessionId,
    required String role,
    String? userText,
    List<dynamic>? blocks,
    String? errorText,
  }) async {
    await _requireDb.insert('chat_messages', {
      'session_id': sessionId,
      'role': role,
      'user_text': userText,
      'blocks_json': blocks != null ? jsonEncode(blocks) : null,
      'error_text': errorText,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> loadMessages({String? sessionId}) async {
    final rows = await _requireDb.query(
      'chat_messages',
      where: sessionId != null ? 'session_id = ?' : null,
      whereArgs: sessionId != null ? [sessionId] : null,
      orderBy: 'id ASC',
    );
    return rows
        .map((row) => {
              'session_id': row['session_id'],
              'role': row['role'],
              'user_text': row['user_text'],
              'blocks': row['blocks_json'] != null ? jsonDecode(row['blocks_json'] as String) : null,
              'error_text': row['error_text'],
              'created_at': row['created_at'],
            })
        .toList();
  }

  /// One row per distinct general-chat session (`preview` is that
  /// session's first user message, for a ChatGPT-style sidebar label),
  /// newest-activity first. Excludes project chats (`session_id` prefixed
  /// `project_` — see ProjectWorkspaceScreen) since those are browsed from
  /// their own project, not this sidebar.
  Future<List<Map<String, dynamic>>> loadSessions() async {
    final rows = await _requireDb.rawQuery('''
      SELECT session_id,
             MAX(created_at) AS last_activity,
             (SELECT user_text FROM chat_messages m2
                WHERE m2.session_id = m1.session_id AND m2.role = 'user'
                ORDER BY m2.id ASC LIMIT 1) AS preview
      FROM chat_messages m1
      WHERE session_id NOT LIKE 'project_%'
      GROUP BY session_id
      ORDER BY last_activity DESC
    ''');
    return rows
        .map((row) => {
              'session_id': row['session_id'] as String,
              'last_activity': row['last_activity'] as String,
              'preview': row['preview'] as String?,
            })
        .toList();
  }

  Future<void> deleteSession(String sessionId) async {
    await _requireDb.delete('chat_messages', where: 'session_id = ?', whereArgs: [sessionId]);
  }

  Future<void> saveActivity({
    String? topic,
    double? score,
    required List<String> labels,
    String? event,
    String? engine,
    required String timestamp,
  }) async {
    await _requireDb.insert('activity_events', {
      'topic': topic,
      'score': score,
      'labels_json': jsonEncode(labels),
      'event': event,
      'engine': engine,
      'timestamp': timestamp,
    });
  }

  Future<List<Map<String, dynamic>>> loadActivityForQuery() async {
    final rows = await _requireDb.query('activity_events', orderBy: 'id DESC', limit: 500);
    return rows
        .map((row) => {
              'topic': row['topic'],
              'score': row['score'],
              'labels': (jsonDecode(row['labels_json'] as String) as List).cast<String>(),
              'timestamp': row['timestamp'],
            })
        .toList();
  }
}
