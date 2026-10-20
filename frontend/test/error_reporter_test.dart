// Crash reports (2026-10-20): each distinct error is sent once per run,
// network failures are skipped, long messages are cut, and a failing send
// never throws.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:study_os_frontend/core/api/api_client.dart';
import 'package:study_os_frontend/core/errors/error_reporter.dart';

class _FakeApi extends ApiClient {
  _FakeApi({this.fail = false}) : super(baseUrl: 'http://test');

  final bool fail;
  final sent = <Map<String, String>>[];

  @override
  Future<void> reportClientError({
    required String message,
    required String stack,
    required String appVersion,
    required String platform,
  }) async {
    if (fail) throw const SocketException('offline');
    sent.add({'message': message, 'stack': stack, 'app_version': appVersion, 'platform': platform});
  }
}

ErrorReporter _reporter(ApiClient api) =>
    ErrorReporter(apiClient: api, appVersion: () async => '1.0.5+6', enabled: true);

void main() {
  test('sends each distinct error once, with version and platform', () async {
    final api = _FakeApi();
    final reporter = _reporter(api);
    final stack = StackTrace.current;
    await reporter.report(StateError('bad state'), stack);
    await reporter.report(StateError('bad state'), stack);
    await reporter.report(ArgumentError('other'), stack);
    expect(api.sent, hasLength(2));
    expect(api.sent.first['message'], 'StateError: Bad state: bad state');
    expect(api.sent.first['app_version'], '1.0.5+6');
    expect(api.sent.first['platform'], isNotEmpty);
  });

  test('skips network failures and cuts long messages', () async {
    final api = _FakeApi();
    final reporter = _reporter(api);
    await reporter.report(const SocketException('no route'), null);
    await reporter.report(TimeoutException('slow'), null);
    expect(api.sent, isEmpty);

    await reporter.report(FormatException('x' * 2000), null);
    expect(api.sent.single['message']!.length, lessThanOrEqualTo(501));
  });

  test('caps reports per run and swallows send failures', () async {
    final api = _FakeApi();
    final reporter = _reporter(api);
    for (var i = 0; i < 15; i++) {
      await reporter.report(StateError('error $i'), null);
    }
    expect(api.sent, hasLength(10));

    await _reporter(_FakeApi(fail: true)).report(StateError('boom'), null); // must not throw
  });

  test('does nothing when disabled (debug builds)', () async {
    final api = _FakeApi();
    await ErrorReporter(apiClient: api, appVersion: () async => 'x', enabled: false).report(StateError('e'), null);
    expect(api.sent, isEmpty);
  });
}
