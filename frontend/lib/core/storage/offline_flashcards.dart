import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';

/// Flashcard review without signal (2026-10-20). The account-wide due
/// cards are kept on the phone after each successful load; a rating that
/// can't reach the server is queued with the time it was made and sent
/// on the next review screen or Home load — the server schedules it from
/// that time (flashcards router's _review_time).
///
/// Small on purpose: the card text of at most [cacheSize] cards plus the
/// pending ratings, in SharedPreferences.
class OfflineFlashcards {
  OfflineFlashcards(this.api);

  final ApiClient api;

  static const cacheSize = 50;
  static const _cacheKey = 'flashcards_due_cache';
  static const _queueKey = 'flashcards_pending_reviews';

  /// No connection or no answer (timeouts arrive as ApiException 0), as
  /// opposed to the server saying no.
  static bool isOffline(Object error) => error is! ApiException || error.statusCode == 0;

  Future<List<Map<String, dynamic>>> _read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> _write(String key, List<Map<String, dynamic>> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(value));
  }

  Future<int> pendingCount() async => (await _read(_queueKey)).length;

  /// Sends queued ratings in order. Stops at the first connection failure
  /// (the rest wait for next time); drops one the server refuses (e.g. the
  /// card was deleted meanwhile). Returns how many were sent.
  Future<int> sync() async {
    final queue = await _read(_queueKey);
    var sent = 0;
    while (queue.isNotEmpty) {
      final next = queue.first;
      try {
        await api.reviewFlashcard(
          flashcardId: next['id'] as int,
          rating: next['rating'] as String,
          reviewedAt: DateTime.parse(next['reviewed_at'] as String),
        );
        sent++;
      } catch (e) {
        if (isOffline(e)) break;
      }
      queue.removeAt(0);
      await _write(_queueKey, queue);
    }
    return sent;
  }

  /// Due cards: from the server when reachable (refreshing the phone's
  /// copy), otherwise the phone's copy minus cards already rated offline.
  /// A subject-scoped review ([knowledgeSpaceSlug]) isn't kept offline, so
  /// it rethrows when there's no connection.
  Future<({List<Map<String, dynamic>> cards, bool offline})> loadDue({String? knowledgeSpaceSlug}) async {
    await sync();
    try {
      final result = await api.getDueFlashcards(knowledgeSpaceSlug: knowledgeSpaceSlug, limit: cacheSize);
      final cards = (result['flashcards'] as List<dynamic>).cast<Map<String, dynamic>>();
      if (knowledgeSpaceSlug == null) await _write(_cacheKey, cards);
      return (cards: cards, offline: false);
    } catch (e) {
      if (knowledgeSpaceSlug != null || !isOffline(e)) rethrow;
      final pending = {for (final r in await _read(_queueKey)) r['id']};
      final cached = (await _read(_cacheKey)).where((c) => !pending.contains(c['id'])).toList();
      return (cards: cached, offline: true);
    }
  }

  /// Rates a card now if possible, otherwise queues it. Returns true when
  /// it was queued (offline). Server refusals are rethrown.
  Future<bool> review(int flashcardId, String rating, {DateTime? now}) async {
    final reviewedAt = now ?? DateTime.now();
    var queued = false;
    try {
      await api.reviewFlashcard(flashcardId: flashcardId, rating: rating);
    } catch (e) {
      if (!isOffline(e)) rethrow;
      final queue = await _read(_queueKey);
      queue.add({'id': flashcardId, 'rating': rating, 'reviewed_at': reviewedAt.toUtc().toIso8601String()});
      await _write(_queueKey, queue);
      queued = true;
    }
    final cache = await _read(_cacheKey);
    cache.removeWhere((c) => c['id'] == flashcardId);
    await _write(_cacheKey, cache);
    return queued;
  }
}
