// AiGenerateButton (2026-10-07) — the shared "Generate with AI" control on
// Concepts, Flashcards and concept practice. Pins the three states a
// student actually sees: busy (with the "can take a minute" note — the
// free model takes minutes), success summary, and the server's own
// actionable error text passed through untouched.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:study_os_frontend/core/api/api_client.dart';
import 'package:study_os_frontend/core/widgets/ai_generate_button.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('shows a busy state, then the success summary, then calls onDone', (tester) async {
    final completer = Completer<String>();
    var done = false;
    await tester.pumpWidget(_wrap(AiGenerateButton(
      label: 'Generate concepts',
      onGenerate: () => completer.future,
      onDone: () => done = true,
    )));

    await tester.tap(find.text('Generate concepts'));
    await tester.pump();
    expect(find.textContaining('this can take a minute'), findsOneWidget);

    completer.complete('Added 3 concepts.');
    await tester.pumpAndSettle();
    expect(find.text('Added 3 concepts.'), findsOneWidget);
    expect(find.text('Generate concepts'), findsOneWidget);
    expect(done, isTrue);
  });

  testWidgets("passes the server's error message through and doesn't call onDone", (tester) async {
    var done = false;
    await tester.pumpWidget(_wrap(AiGenerateButton(
      label: 'Generate',
      onGenerate: () async => throw ApiException(503, 'add your own API key in Account settings'),
      onDone: () => done = true,
    )));
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();
    expect(find.text('add your own API key in Account settings'), findsOneWidget);
    expect(done, isFalse);
  });

  test('generatedSummary counts new and skipped rows', () {
    expect(generatedSummary({'concepts': [1, 2], 'skipped_existing': 1}, 'concepts', 'concept'),
        'Added 2 concepts (1 already existed).');
    expect(generatedSummary({'flashcards': [1]}, 'flashcards', 'flashcard'), 'Added 1 flashcard.');
    expect(generatedSummary({'questions': [], 'skipped_existing': 4}, 'questions', 'question'),
        'Nothing new — all 4 already existed.');
  });
}
