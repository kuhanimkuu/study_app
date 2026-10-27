import 'dart:io' show SocketException;
import 'dart:math';

import 'package:http/http.dart' as http;

/// Makes repeated requests safe (2026-10-27) — the app's half of
/// server/core/idempotency.py.
///
/// Every request that changes something (POST/PUT/PATCH/DELETE) carries an
/// `Idempotency-Key`. The same request sent again — after a timeout, a
/// dropped connection or a double tap — carries the same key, so the server
/// sends back the first answer instead of creating a second lesson,
/// flashcard, upload or AI charge. "The same request" is the same method,
/// address and body, while the first is still running or until it has
/// succeeded; after a success the next identical request is a new action
/// (a second "make flashcards" really makes more) — unless the app gave up
/// waiting for that success, see [pinInFlight].
///
/// A connection that drops before an answer arrives is retried once by
/// itself, with the same key.
class IdempotentClient extends http.BaseClient {
  IdempotentClient(this._inner, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final http.Client _inner;
  final DateTime Function() _clock;

  /// How long a key is kept for a request that failed or was given up on.
  static const keepFor = Duration(minutes: 10);
  static const _methods = {'POST', 'PUT', 'PATCH', 'DELETE'};
  static final _random = Random.secure();

  final Map<String, _Entry> _entries = {};

  /// Called when the app stops waiting for an answer (a timeout): whatever
  /// is still running may yet succeed on the server, so a repeat of it must
  /// keep the same key even after that success arrives here.
  void pinInFlight() {
    final now = _clock();
    for (final entry in _entries.values) {
      if (entry.inFlight > 0) {
        entry.pinned = true;
        entry.lastUsed = now;
      }
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!_methods.contains(request.method)) return _inner.send(request);
    _prune();
    final fingerprint = _fingerprint(request);
    final entry = _entries.putIfAbsent(fingerprint, () => _Entry(_newKey(), _clock()));
    entry
      ..inFlight += 1
      ..lastUsed = _clock();
    request.headers['Idempotency-Key'] = entry.key;
    try {
      final response = await _sendRetryingOnce(request);
      if (response.statusCode >= 200 && response.statusCode < 300 && !entry.pinned) {
        _entries.remove(fingerprint); // done: the next identical request is a new action
      } else {
        entry.lastUsed = _clock(); // a retry of this should reuse the key
      }
      return response;
    } catch (_) {
      entry.lastUsed = _clock();
      rethrow;
    } finally {
      entry.inFlight -= 1;
    }
  }

  Future<http.StreamedResponse> _sendRetryingOnce(http.BaseRequest request) async {
    // A plain request can be rebuilt and sent again; an upload's body
    // stream can't, so uploads aren't retried here (their key still
    // protects a retry the student starts).
    final copy = request is http.Request ? _copy(request) : null;
    try {
      return await _inner.send(request);
    } on Exception catch (e) {
      if (copy == null || !(e is SocketException || e is http.ClientException)) rethrow;
      return _inner.send(copy);
    }
  }

  static http.Request _copy(http.Request request) => http.Request(request.method, request.url)
    ..headers.addAll(request.headers)
    ..bodyBytes = request.bodyBytes
    ..followRedirects = request.followRedirects;

  static String _fingerprint(http.BaseRequest request) {
    final body = switch (request) {
      http.Request r => '${r.bodyBytes.length}:${Object.hashAll(r.bodyBytes)}',
      http.MultipartRequest r => [
          for (final f in (r.fields.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) '${f.key}=${f.value}',
          for (final f in r.files) '${f.field}:${f.filename}:${f.length}',
        ].join('&'),
      _ => '${request.contentLength}',
    };
    return '${request.method} ${request.url} $body';
  }

  void _prune() {
    final cutoff = _clock().subtract(keepFor);
    _entries.removeWhere((_, e) => e.inFlight == 0 && e.lastUsed.isBefore(cutoff));
  }

  static String _newKey() => List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  @override
  void close() => _inner.close();
}

class _Entry {
  _Entry(this.key, this.lastUsed);

  final String key;
  DateTime lastUsed;
  int inFlight = 0;
  bool pinned = false;
}
