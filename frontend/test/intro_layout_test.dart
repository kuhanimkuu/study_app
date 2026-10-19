// Every intro page must fit a small phone (360x640) without overflowing,
// including at a larger system text size — the BYOK page's longer copy
// overflowed by 340 px before the page layout let its text scroll
// (2026-10-19).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:study_os_frontend/core/api/api_client.dart';
import 'package:study_os_frontend/main.dart';

void main() {
  for (final scale in [1.0, 1.3]) {
    testWidgets('every intro page fits a 360x640 phone at text scale $scale', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(StudyOsApp(apiClient: ApiClient(baseUrl: 'http://127.0.0.1:8000')));
      await tester.pumpAndSettle();
      // an overflow anywhere fails the test through the framework's error reporting
      while (find.text('Next').evaluate().isNotEmpty) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Get started'), findsOneWidget);
    });
  }
}
