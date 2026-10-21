// AI setup (2026-10-21): until a key is added, a loud banner says Sage
// can't answer; the setup tests the key with the server before saving it,
// and shows the server's plain-words reason when it fails.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:study_os_frontend/core/api/api_client.dart';
import 'package:study_os_frontend/core/auth/auth_service.dart';
import 'package:study_os_frontend/core/settings/model_settings_service.dart';
import 'package:study_os_frontend/features/account/ai_setup/ai_setup.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

// A real 32-byte AES key, base64 (what the server issues per user).
const _userKey = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=';

Future<AuthService> _signedIn(http.Response Function(http.Request) server) async {
  final api = ApiClient(baseUrl: 'http://test', httpClient: MockClient((r) async => server(r)));
  final auth = AuthService(apiClient: api, modelSettings: ModelSettingsService());
  await auth.debugSignIn({'id': 1, 'email': 'a@b.co'}, _userKey);
  AiSetup.attach(auth);
  return auth;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('no key: the banner says so and opens the setup', (tester) async {
    await _signedIn((_) => _json({}));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AiSetupBanner())));
    expect(find.text('Sage needs an AI key to work'), findsOneWidget);

    await tester.tap(find.text('Set up AI now'));
    await tester.pumpAndSettle();
    expect(find.text('1. Choose a provider'), findsOneWidget);
    expect(find.text('Recommended'), findsOneWidget);
  });

  testWidgets('a rejected key shows why, and nothing is saved', (tester) async {
    final auth = await _signedIn((request) {
      expect(request.url.path, '/api/v1/ai/check');
      return _json({'detail': "DeepSeek didn't accept that key. Copy it again from DeepSeek's API keys page."}, 400);
    });
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AiSetupBanner())));
    await tester.tap(find.text('Set up AI now'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.byType(TextField), 200);
    await tester.enterText(find.byType(TextField), 'sk-wrong');
    await tester.ensureVisible(find.text('Test and save'));
    await tester.tap(find.text('Test and save'));
    await tester.pumpAndSettle();
    expect(find.textContaining("didn't accept that key"), findsOneWidget);
    expect(auth.modelSettings.aiReady, isFalse);
  });

  testWidgets('a working key is saved, and the banner goes away', (tester) async {
    late Map<String, dynamic> sent;
    final auth = await _signedIn((request) {
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return _json({'ok': true, 'provider': 'DeepSeek'});
    });
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AiSetupBanner())));
    await tester.tap(find.text('Set up AI now'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.byType(TextField), 200);
    await tester.enterText(find.byType(TextField), 'sk-real-key');
    await tester.ensureVisible(find.text('Test and save'));
    await tester.tap(find.text('Test and save'));
    await tester.pumpAndSettle();
    expect(find.text('Sage is ready!'), findsOneWidget);
    expect(sent['model_config']['backend'], 'deepseek');
    expect(sent['model_config']['encrypted_api_key'], isNot(contains('sk-real-key'))); // encrypted, not plain
    expect(auth.modelSettings.aiReady, isTrue);

    await tester.tap(find.text('Start learning'));
    await tester.pumpAndSettle();
    expect(find.text('Sage needs an AI key to work'), findsNothing);
  });
}
