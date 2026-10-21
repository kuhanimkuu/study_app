// The app shows its version (2026-10-21) — read from the installed package.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:study_os_frontend/core/widgets/app_version_text.dart';

void main() {
  testWidgets('shows the version and build number', (tester) async {
    final info = PackageInfo(appName: 'Study OS', packageName: 'x', version: '1.0.9', buildNumber: '10');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AppVersionText(info: info))));
    await tester.pumpAndSettle();
    expect(find.text('Study OS 1.0.9 (build 10)'), findsOneWidget);
  });
}
