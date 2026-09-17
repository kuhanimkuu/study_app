// Smoke tests: the app boots into AuthGate and, with no saved session,
// lands on the feature-intro tour on a device that's never seen it (or
// straight on the login screen once that flag is set) — not the chat
// screen directly anymore now that auth is required (see
// core/auth/auth_service.dart). Doesn't hit a real server (none running
// under a test) — see server/README.md for the end-to-end HTTP testing
// that covers the authenticated flow.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:study_os_frontend/core/api/api_client.dart';
import 'package:study_os_frontend/main.dart';

void main() {
  testWidgets('First launch on a device shows the feature intro tour', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(StudyOsApp(apiClient: ApiClient(baseUrl: 'http://127.0.0.1:8000')));
    await tester.pumpAndSettle();

    expect(find.text('Get started'), findsNothing); // not yet on the last page
    expect(find.text('Next'), findsOneWidget);

    // Skipping the tour lands on the login screen.
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('Log in'), findsWidgets);
  });

  testWidgets('App boots with no saved session but a seen intro and shows the login screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'intro_seen': true});
    await tester.pumpWidget(StudyOsApp(apiClient: ApiClient(baseUrl: 'http://127.0.0.1:8000')));
    await tester.pumpAndSettle();

    expect(find.text('Log in'), findsWidgets);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });
}
