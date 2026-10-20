// Home's exam countdown (2026-10-20): picks the nearest goal dated today
// or later, ignores past and undated goals.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:study_os_frontend/features/home/presentation/widgets/exam_countdown.dart';

void main() {
  final now = DateTime(2026, 10, 20, 15);
  String on(int y, int m, int d) => DateTime(y, m, d, 9).toUtc().toIso8601String();

  test('picks the nearest upcoming dated goal', () {
    final exam = nextExam([
      {'title': 'Past quiz', 'target_date': on(2026, 10, 19)},
      {'title': 'No date', 'target_date': null},
      {'title': 'Physics final', 'target_date': on(2026, 11, 30)},
      {'title': 'Biology mock', 'target_date': on(2026, 11, 2)},
    ], now);
    expect(exam!.goal['title'], 'Biology mock');
    expect(exam.daysLeft, 13);
  });

  test('today counts; nothing upcoming gives null', () {
    expect(nextExam([{'title': 'Today', 'target_date': on(2026, 10, 20)}], now)!.daysLeft, 0);
    expect(nextExam([{'title': 'Past', 'target_date': on(2026, 1, 1)}], now), isNull);
    expect(daysLeftLabel(0), 'Today');
    expect(daysLeftLabel(1), 'Tomorrow');
    expect(daysLeftLabel(9), 'In 9 days');
  });

  testWidgets('card shows the days and title', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ExamCountdownCard(title: 'Biology mock', daysLeft: 13))));
    expect(find.text('13'), findsOneWidget);
    expect(find.text('Biology mock'), findsOneWidget);
    expect(find.text('Your study plan is counting down to this.'), findsOneWidget);
  });
}
