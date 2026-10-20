// Offline flashcards (2026-10-20): due cards are kept on the phone, ratings
// made without signal are queued with their time and synced in order, and a
// refused rating is dropped rather than retried forever.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:study_os_frontend/core/api/api_client.dart';
import 'package:study_os_frontend/core/storage/offline_flashcards.dart';

class _FakeApi extends ApiClient {
  _FakeApi() : super(baseUrl: 'http://test');

  bool online = true;
  final Set<int> deleted = {};
  final reviews = <(int, String, DateTime?)>[];
  final cards = [
    {'id': 1, 'front': 'Mitochondria?', 'back': 'Powerhouse'},
    {'id': 2, 'front': 'Osmosis?', 'back': 'Water moving'},
    {'id': 3, 'front': 'ATP?', 'back': 'Energy'},
  ];

  @override
  Future<Map<String, dynamic>> getDueFlashcards({String? knowledgeSpaceSlug, int limit = 20}) async {
    if (!online) throw const SocketException('offline');
    return {'flashcards': List.of(cards)};
  }

  @override
  Future<Map<String, dynamic>> reviewFlashcard({required int flashcardId, required String rating, DateTime? reviewedAt}) async {
    if (!online) throw const SocketException('offline');
    if (deleted.contains(flashcardId)) throw ApiException(404, 'flashcard not found');
    reviews.add((flashcardId, rating, reviewedAt));
    cards.removeWhere((c) => c['id'] == flashcardId);
    return {};
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('works offline from the saved copy and syncs ratings with their time', () async {
    final api = _FakeApi();
    final store = OfflineFlashcards(api);

    final online = await store.loadDue();
    expect(online.offline, isFalse);
    expect(online.cards, hasLength(3));

    api.online = false;
    final ratedAt = DateTime.utc(2026, 10, 20, 8, 30);
    expect(await store.review(1, 'good', now: ratedAt), isTrue);
    expect(await store.review(2, 'again', now: ratedAt.add(const Duration(minutes: 1))), isTrue);

    final offline = await store.loadDue();
    expect(offline.offline, isTrue);
    expect(offline.cards.map((c) => c['id']), [3]); // rated ones don't come back
    expect(await store.pendingCount(), 2);

    api.online = true;
    expect(await store.sync(), 2);
    expect(api.reviews.map((r) => (r.$1, r.$2)), [(1, 'good'), (2, 'again')]);
    expect(api.reviews.first.$3, ratedAt);
    expect(await store.pendingCount(), 0);
  });

  test('a rating the server refuses is dropped, not retried forever', () async {
    final api = _FakeApi()..online = false;
    final store = OfflineFlashcards(api);
    await store.review(1, 'good');
    await store.review(2, 'easy');
    api
      ..online = true
      ..deleted.add(1);
    expect(await store.sync(), 1);
    expect(await store.pendingCount(), 0);
    expect(api.reviews.single.$1, 2);
  });

  test('subject reviews need a connection; server errors are not treated as offline', () async {
    final api = _FakeApi()..online = false;
    final store = OfflineFlashcards(api);
    expect(() => store.loadDue(knowledgeSpaceSlug: 'bio'), throwsA(isA<SocketException>()));

    expect(OfflineFlashcards.isOffline(ApiException(0, 'timed out')), isTrue);
    expect(OfflineFlashcards.isOffline(ApiException(500, 'server error')), isFalse);
  });
}
