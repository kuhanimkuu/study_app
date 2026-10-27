// Go deeper (2026-10-27): real sources picked by Sage, a video shown with
// the section worth watching and what it covers, and a way to report a
// source. The server is faked.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:study_os_frontend/core/api/api_client.dart';
import 'package:study_os_frontend/features/chat/presentation/widgets/block_view.dart';
import 'package:study_os_frontend/features/research/go_deeper_screen.dart';
import 'package:study_os_frontend/features/research/video_player_screen.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

const _video = {
  'id': 'abcdefghijk', 'channel': 'Bio Lab', 'start': 95, 'end': 400, 'section': 'Light reactions',
  'covers': 'How light energy is turned into ATP', 'chapters': [
    {'start': 0, 'title': 'Intro'},
    {'start': 95, 'title': 'Light reactions'},
  ],
};

void main() {
  test('section labels', () {
    expect(sectionLabel({'start': 95, 'end': 400}), 'Watch 1:35–6:40');
    expect(sectionLabel({'start': 3725}), 'Starts at 1:02:05');
    expect(sectionLabel({'start': 0}), isNull);
  });

  testWidgets('a pasted video shows what to watch', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BlockView(
            block: {'type': 'video', 'title': 'Photosynthesis explained', 'url': 'https://youtu.be/abcdefghijk', ..._video},
            baseUrl: 'http://test',
          ),
        ),
      ),
    ));
    expect(find.text('Photosynthesis explained'), findsOneWidget);
    expect(find.text('Watch 1:35–6:40'), findsOneWidget);
    expect(find.text('Section: Light reactions'), findsOneWidget);
    expect(find.text('How light energy is turned into ATP'), findsOneWidget);
  });

  testWidgets('Go deeper lists real sources and reports one', (tester) async {
    final calls = <String>[];
    Map<String, dynamic>? reported;
    final api = ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient((request) async {
        calls.add(request.url.path);
        if (request.url.path == '/api/v1/sources/report') {
          reported = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({'reported': true, 'message': 'Thanks — we’ll look at it.'});
        }
        return _json({
          'level': 'beginner',
          'picked_by': 'ai',
          'items': [
            {'kind': 'video', 'title': 'Photosynthesis explained', 'url': 'https://www.youtube.com/watch?v=abcdefghijk',
             'reason': 'Short and clear', 'attribution': 'by Bio Lab, on YouTube', 'video': _video},
            {'kind': 'article', 'title': 'Photosynthesis', 'url': 'https://en.wikipedia.org/wiki/Photosynthesis',
             'excerpt': 'Photosynthesis is a system of biological processes…', 'licence': 'CC BY-SA',
             'attribution': '“Photosynthesis”, Wikipedia — CC BY-SA 4.0', 'reason': 'Background reading', 'tier': 'A'},
          ],
        });
      }),
    );
    await tester.pumpWidget(MaterialApp(home: GoDeeperScreen(apiClient: api, topic: 'photosynthesis')));
    await tester.pumpAndSettle();
    expect(find.text('Picked for you from real sources'), findsOneWidget);
    expect(find.text('Short and clear'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Background reading'), 200);
    expect(find.textContaining('CC BY-SA'), findsWidgets);

    await tester.ensureVisible(find.text('Report').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'wrong information');
    await tester.tap(find.widgetWithText(FilledButton, 'Report'));
    await tester.pumpAndSettle();
    expect(reported, {'url': 'https://en.wikipedia.org/wiki/Photosynthesis', 'reason': 'wrong information'});
    expect(calls.first, '/api/v1/go-deeper');
  });
}
