// Login under a bot flood (2026-10-21): a 503 "server busy" from login is
// retried quietly and gets in; a wrong password or the per-address 429
// limit is shown at once, never retried.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:study_os_frontend/core/api/api_client.dart';

ApiClient _client(List<int> statuses, List<String> calls) {
  var i = 0;
  return ApiClient(
    baseUrl: 'http://test',
    httpClient: MockClient((request) async {
      calls.add(request.url.path);
      final status = statuses[i < statuses.length ? i : statuses.length - 1];
      i++;
      final body = status == 200 ? {'token': 't', 'user': {'id': 1}} : {'detail': 'status $status'};
      return http.Response(jsonEncode(body), status);
    }),
  );
}

void main() {
  setUp(() => ApiClient.busyRetryDelays = const [Duration.zero, Duration.zero, Duration.zero]);

  test('busy answers are retried until the login gets in', () async {
    final calls = <String>[];
    final result = await _client([503, 503, 200], calls).login(email: 'a@b.c', password: 'pw123456');
    expect(result['token'], 't');
    expect(calls, hasLength(3));
  });

  test('gives up after the retries and shows the busy message', () async {
    final calls = <String>[];
    await expectLater(
      _client([503], calls).signup(email: 'a@b.c', password: 'pw123456'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 503)),
    );
    expect(calls, hasLength(4)); // first try + 3 retries
  });

  test('wrong password and the per-address limit are not retried', () async {
    for (final status in [401, 429]) {
      final calls = <String>[];
      await expectLater(
        _client([status], calls).login(email: 'a@b.c', password: 'pw123456'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', status)),
      );
      expect(calls, hasLength(1), reason: '$status');
    }
  });
}
