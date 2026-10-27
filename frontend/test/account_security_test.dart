// Account security from the 2026-10-21 audit: a device signed out from
// elsewhere (password change, "sign out everywhere") goes back to the login
// screen; changing the password hands back the token that keeps this device
// in; the AI meter sends the phone's UTC offset; the data export returns
// the file's bytes.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:study_os_frontend/core/api/api_client.dart';

ApiClient _client(http.Response Function(http.Request request) handler) =>
    ApiClient(baseUrl: 'http://test', httpClient: MockClient((request) async => handler(request)));

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

void main() {
  test('a revoked sign-in triggers onSignedOut', () async {
    final client = _client((_) => _json({'detail': 'you were signed out — please log in again'}, 401))..token = 'old';
    var signedOut = 0;
    client.onSignedOut = () => signedOut++;
    await expectLater(client.me(), throwsA(isA<ApiException>()));
    expect(signedOut, 1);
  });

  test('a wrong password is not mistaken for being signed out', () async {
    final client = _client((_) => _json({'detail': 'current password is incorrect'}, 401))..token = 't';
    var signedOut = 0;
    client.onSignedOut = () => signedOut++;
    await expectLater(
      client.changePassword(currentPassword: 'nope', newPassword: 'newpass456'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
    );
    expect(signedOut, 0);
  });

  test('changing the password returns the new token for this device', () async {
    late Map<String, dynamic> sent;
    final client = _client((request) {
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return _json({'token': 'fresh'});
    })..token = 't';
    expect(await client.changePassword(currentPassword: 'old', newPassword: 'newpass456'), 'fresh');
    expect(sent, {'current_password': 'old', 'new_password': 'newpass456'});

    // A Google-only account sets its first password without a current one.
    await client.changePassword(newPassword: 'newpass456');
    expect(sent.containsKey('current_password'), isFalse);
  });

  test("the AI meter asks for the phone's own day", () async {
    late Uri asked;
    final client = _client((request) {
      asked = request.url;
      return _json({});
    })..token = 't';
    await client.getAiUsage();
    expect(asked.queryParameters['tz_offset_minutes'], '${DateTime.now().timeZoneOffset.inMinutes}');
  });

  test('chat questions carry the depth and tutor mode', () async {
    late Map<String, dynamic> sent;
    final client = _client((request) {
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return _json({'blocks': [], 'session_id': 's'});
    })..token = 't';
    await client.askText(content: 'explain entropy', sessionId: 's', depth: 'exam', tutorMode: false);
    expect(sent['depth'], 'exam');
    expect(sent['tutor_mode'], false);
  });

  test('the data export returns the file bytes', () async {
    final client = _client((_) => http.Response('{"account": {}}', 200))..token = 't';
    expect(utf8.decode(await client.exportAccountData()), '{"account": {}}');
  });
}
