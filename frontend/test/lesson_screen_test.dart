// Lessons (2026-10-21): a whole lesson against a fake server — read a
// step, answer its check, see whether it was right and why, continue, then
// finish and save the recap as flashcards.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:study_os_frontend/core/api/api_client.dart';
import 'package:study_os_frontend/features/tutor/lessons/lesson_screen.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> _lesson() => {
      'id': 7,
      'title': 'Osmosis',
      'status': 'in_progress',
      'checks': 2,
      'answered': 0,
      'correct': 0,
      'worked_example': null,
      'recap': [
        {'front': 'Osmosis', 'back': 'Water across a membrane'},
      ],
      'lesson_steps': [
        {
          'heading': 'Water moves',
          'explanation': 'Water moves across a **membrane**.',
          'question': {'id': 1, 'type': 'mcq', 'prompt': 'What moves?', 'options': ['Water', 'Salt']},
          'result': null,
        },
        {
          'heading': 'Which way',
          'explanation': 'Towards more solute.',
          'question': {'id': 2, 'type': 'true_false', 'prompt': 'Water moves to more solute.'},
          'result': null,
        },
      ],
    };

void main() {
  testWidgets('a whole lesson, step by step', (tester) async {
    final calls = <String>[];
    final api = ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        final path = request.url.path;
        if (path == '/api/v1/lessons') return _json(_lesson());
        if (path.endsWith('/steps/0/answer')) {
          return _json({
            'correct': false, 'answer': 'Salt', 'feedback': null, 'why': 'Osmosis is about water.',
            'correct_answer': 'Water', 'lesson': {'answered': 1, 'correct': 0},
          });
        }
        if (path.endsWith('/steps/1/answer')) {
          return _json({
            'correct': true, 'answer': 'true', 'feedback': null, 'why': 'It dilutes it.',
            'correct_answer': 'true', 'lesson': {'answered': 2, 'correct': 1},
          });
        }
        if (path.endsWith('/complete')) {
          return _json({'lesson': {..._lesson(), 'status': 'completed', 'answered': 2, 'correct': 1}, 'flashcards_added': 1});
        }
        return _json({'detail': 'unexpected $path'}, 404);
      }),
    );

    await tester.pumpWidget(MaterialApp(home: LessonScreen(apiClient: api, topic: 'osmosis')));
    await tester.pumpAndSettle();
    expect(find.text('Water moves'), findsOneWidget);
    expect(find.text('Step 1 of 2'), findsOneWidget);

    await tester.tap(find.text('Salt'));
    await tester.tap(find.text('Check my answer'));
    await tester.pumpAndSettle();
    expect(find.text('Not quite'), findsOneWidget);
    expect(find.text('Answer: Water'), findsOneWidget);
    expect(find.text('Osmosis is about water.'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Which way'), findsOneWidget);
    await tester.tap(find.text('True'));
    await tester.tap(find.text('Check my answer'));
    await tester.pumpAndSettle();
    expect(find.text('Got it!'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('What to remember'), findsOneWidget);
    await tester.tap(find.text('Finish and save 1 flashcard'));
    await tester.pumpAndSettle();
    expect(find.text('Lesson complete!'), findsOneWidget);
    expect(find.text('You got 1 of 2 checks right.'), findsOneWidget);
    expect(calls, [
      'POST /api/v1/lessons',
      'POST /api/v1/lessons/7/steps/0/answer',
      'POST /api/v1/lessons/7/steps/1/answer',
      'POST /api/v1/lessons/7/complete',
    ]);
  });

  testWidgets('without a topic it asks what to learn', (tester) async {
    final api = ApiClient(baseUrl: 'http://test', httpClient: MockClient((_) async => _json({'projects': []})));
    await tester.pumpWidget(MaterialApp(home: LessonScreen(apiClient: api)));
    await tester.pumpAndSettle();
    expect(find.text('What do you want to learn?'), findsOneWidget);
    await tester.tap(find.text('Start the lesson'));
    await tester.pumpAndSettle();
    expect(find.text('Type what you want to learn.'), findsOneWidget);
  });
}
