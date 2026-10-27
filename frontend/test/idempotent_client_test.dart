// Repeated requests are safe (2026-10-27): every change carries an
// Idempotency-Key, a repeat after a failure or a timeout reuses it, a new
// action after a success gets a new one, and a dropped connection is
// retried once with the same key.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:study_os_frontend/core/api/idempotent_client.dart';

void main() {
  late List<http.Request> seen;
  late List<Object> plan; // what each call does: an int status, or an exception to throw

  IdempotentClient client() => IdempotentClient(MockClient((request) async {
        seen.add(request);
        final next = plan.isEmpty ? 200 : plan.removeAt(0);
        if (next is Exception) throw next;
        return http.Response('{}', next as int);
      }));

  setUp(() {
    seen = [];
    plan = [];
  });

  Future<void> post(IdempotentClient c, [String body = '{"a":1}']) async {
    try {
      await c.post(Uri.parse('http://test/api/projects'), body: body);
    } catch (_) {}
  }

  String key(int i) => seen[i].headers['Idempotency-Key']!;

  test('reads carry no key', () async {
    await client().get(Uri.parse('http://test/api/projects'));
    expect(seen.single.headers.containsKey('Idempotency-Key'), isFalse);
  });

  test('a repeat after a failure reuses the key; after a success it is a new action', () async {
    final c = client();
    plan = [500, 200, 200];
    await post(c); // fails
    await post(c); // the retry: same key
    await post(c); // after a success: a new action
    expect(key(1), key(0));
    expect(key(2), isNot(key(1)));
  });

  test('a different body is a different request', () async {
    final c = client();
    plan = [500, 200];
    await post(c, '{"a":1}');
    await post(c, '{"a":2}');
    expect(key(1), isNot(key(0)));
  });

  test('a dropped connection is retried once, with the same key', () async {
    plan = [http.ClientException('connection reset'), 200];
    final response = await client().post(Uri.parse('http://test/api/v1/lessons'), body: '{}');
    expect(response.statusCode, 200);
    expect(seen, hasLength(2));
    expect(key(1), key(0));
  });

  test('after a timeout, even a later success keeps the key for the retry', () async {
    final c = client();
    final first = c.post(Uri.parse('http://test/api/v1/lessons'), body: '{}');
    c.pinInFlight(); // what ApiClient does when it stops waiting
    await first; // ...and the server finished after all
    await c.post(Uri.parse('http://test/api/v1/lessons'), body: '{}');
    expect(seen.last.headers['Idempotency-Key'], key(0));
  });
}
