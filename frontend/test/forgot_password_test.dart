// "Forgot password?" (2026-10-21): the email step sends a code and shows
// the code + new password step; a wrong code shows the server's message.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:study_os_frontend/core/api/api_client.dart';
import 'package:study_os_frontend/core/auth/auth_service.dart';
import 'package:study_os_frontend/core/settings/model_settings_service.dart';
import 'package:study_os_frontend/features/auth/presentation/screens/forgot_password_screen.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

void main() {
  testWidgets('send a code, then a wrong code shows why', (tester) async {
    final calls = <String>[];
    final api = ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient((request) async {
        calls.add(request.url.path);
        if (request.url.path.endsWith('/request')) {
          return _json({'message': "If an account uses that email, we've sent it a 6-digit code."});
        }
        return _json({'detail': 'That code is wrong or has expired.'}, 400);
      }),
    );
    final auth = AuthService(apiClient: api, modelSettings: ModelSettingsService());
    await tester.pumpWidget(MaterialApp(home: ForgotPasswordScreen(authService: auth, initialEmail: 'a@b.co')));

    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(find.textContaining("we've sent it a 6-digit code"), findsOneWidget);
    expect(find.text('6-digit code'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '6-digit code'), '123456');
    await tester.enterText(find.widgetWithText(TextField, 'New password'), 'brandnew456');
    await tester.enterText(find.widgetWithText(TextField, 'New password again'), 'brandnew456');
    await tester.tap(find.text('Set new password'));
    await tester.pumpAndSettle();
    expect(find.text('That code is wrong or has expired.'), findsOneWidget);
    expect(calls, ['/api/auth/password-reset/request', '/api/auth/password-reset/confirm']);
  });

  testWidgets('mismatched passwords are caught before asking the server', (tester) async {
    var called = 0;
    final api = ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient((_) async {
        called++;
        return _json({'message': 'sent'});
      }),
    );
    final auth = AuthService(apiClient: api, modelSettings: ModelSettingsService());
    await tester.pumpWidget(MaterialApp(home: ForgotPasswordScreen(authService: auth, initialEmail: 'a@b.co')));
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '6-digit code'), '123456');
    await tester.enterText(find.widgetWithText(TextField, 'New password'), 'brandnew456');
    await tester.enterText(find.widgetWithText(TextField, 'New password again'), 'different99');
    await tester.tap(find.text('Set new password'));
    await tester.pumpAndSettle();
    expect(find.text("The two passwords don't match."), findsOneWidget);
    expect(called, 1);
  });
}
