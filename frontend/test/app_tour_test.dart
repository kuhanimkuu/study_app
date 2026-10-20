// The first-run tour (app/app_tour.dart, 2026-10-19): Sage walks a new
// student through each part of the app once, with a spotlight on each tab.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:study_os_frontend/app/app_tour.dart';
import 'package:study_os_frontend/app/theme.dart';

final _homeKey = GlobalKey();
final _planKey = GlobalKey();

List<AppTourStep> _steps() => [
      const AppTourStep(title: 'Welcome to Study OS!', body: 'Intro', color: StudyOsColors.primary, icon: Icons.waving_hand_rounded),
      AppTourStep(target: _homeKey, title: 'Home', body: 'Your daily goal', color: StudyOsColors.primary, icon: Icons.home_rounded),
      AppTourStep(target: _planKey, title: 'Plan', body: 'Goals and sessions', color: StudyOsColors.streak, icon: Icons.calendar_month_rounded),
    ];

Widget _app({required VoidCallback onDone}) => MaterialApp(
      theme: studyOsLightTheme,
      home: Stack(
        children: [
          Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: SizedBox(
              height: 72,
              child: Row(
                children: [
                  Expanded(child: Center(key: _homeKey, child: const Text('home tab'))),
                  Expanded(child: Center(key: _planKey, child: const Text('plan tab'))),
                ],
              ),
            ),
          ),
          Positioned.fill(child: AppTourOverlay(steps: _steps(), onDone: onDone)),
        ],
      ),
    );

void main() {
  testWidgets('walks through every step, with Back, and finishes on the last', (tester) async {
    var done = 0;
    await tester.pumpWidget(_app(onDone: () => done++));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Study OS!'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    // the spotlit target is in the lower half, so the card sits above it
    expect(tester.getBottomLeft(find.text('Home')).dy, lessThan(tester.getTopLeft(find.byKey(_homeKey)).dy));

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Study OS!'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('Skip tour'), findsNothing); // nothing left to skip on the last step
    expect(done, 0);

    await tester.tap(find.text("Let's go!"));
    await tester.pumpAndSettle();
    expect(done, 1);
  });

  testWidgets('Skip tour ends it straight away', (tester) async {
    var done = 0;
    await tester.pumpWidget(_app(onDone: () => done++));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip tour'));
    expect(done, 1);
  });

  testWidgets('a step whose target is missing still shows (centred), without looping', (tester) async {
    final missing = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      theme: studyOsLightTheme,
      home: AppTourOverlay(
        steps: [AppTourStep(target: missing, title: 'Profile', body: 'Not on screen', color: StudyOsColors.primary, icon: Icons.person)],
        onDone: () {},
      ),
    ));
    await tester.pumpAndSettle(); // would time out if it re-checked every frame forever
    expect(find.text('Profile'), findsOneWidget);
  });

  test('shown once per device, and can be requested again', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await AppTour.shouldShow(), isTrue);
    await AppTour.markSeen();
    expect(await AppTour.shouldShow(), isFalse);

    AppTour.requestReplay();
    expect(AppTour.replayRequested.value, isTrue);
    AppTour.replayRequested.value = false;
  });
}
