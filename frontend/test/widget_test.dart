// Smoke test: the app boots into AuthGate and, with no saved session,
// lands on the login screen — not the chat screen directly anymore now
// that auth is required (see core/auth/auth_service.dart). Doesn't hit a
// real server (none running under a test) — see server/README.md for the
// end-to-end HTTP testing that covers the authenticated flow.

import 'package:flutter_test/flutter_test.dart';

import 'package:study_os_frontend/core/api/api_client.dart';
import 'package:study_os_frontend/main.dart';

void main() {
  testWidgets('App boots with no saved session and shows the login screen', (WidgetTester tester) async {
    await tester.pumpWidget(StudyOsApp(apiClient: ApiClient(baseUrl: 'http://127.0.0.1:8000')));
    await tester.pumpAndSettle();

    expect(find.text('Log in'), findsWidgets);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });
}
