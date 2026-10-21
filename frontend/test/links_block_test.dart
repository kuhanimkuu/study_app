// The project chat's "Learn more" card (2026-10-21): real links render as
// tappable rows; anything that isn't an http(s) link is never shown.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:study_os_frontend/features/chat/presentation/widgets/block_view.dart';
import 'package:study_os_frontend/features/chat/presentation/widgets/blocks/links_block.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  testWidgets('a links block shows each real link with its site', (tester) async {
    await tester.pumpWidget(_wrap(const BlockView(
      block: {
        'type': 'links',
        'title': 'Learn more',
        'links': [
          {'label': 'Wikipedia: photosynthesis', 'url': 'https://en.wikipedia.org/w/index.php?search=photosynthesis'},
          {'label': 'Sneaky', 'url': 'javascript:alert(1)'},
          {'label': 'Khan Academy: photosynthesis', 'url': 'https://www.khanacademy.org/search?page_search_query=photosynthesis'},
        ],
      },
      baseUrl: 'http://test',
    )));
    expect(find.text('Learn more'), findsOneWidget);
    expect(find.text('Wikipedia: photosynthesis'), findsOneWidget);
    expect(find.text('en.wikipedia.org'), findsOneWidget);
    expect(find.text('khanacademy.org'), findsOneWidget);
    expect(find.text('Sneaky'), findsNothing);
    expect(find.byType(LinkRow), findsNWidgets(2));
  });

  testWidgets("a web result's address is tappable", (tester) async {
    await tester.pumpWidget(_wrap(const BlockView(
      block: {'type': 'source', 'content': 'BBC Bitesize: photosynthesis', 'source': 'https://www.bbc.co.uk/bitesize'},
      baseUrl: 'http://test',
    )));
    expect(find.byType(LinkRow), findsOneWidget);
  });

  testWidgets('a passage from the notes stays plain text', (tester) async {
    await tester.pumpWidget(_wrap(const BlockView(
      block: {'type': 'source', 'content': 'Mitosis is...', 'source': 'Source 1 · match 80%'},
      baseUrl: 'http://test',
    )));
    expect(find.byType(LinkRow), findsNothing);
    expect(find.text('Source 1 · match 80%'), findsOneWidget);
  });

  test('only http(s) addresses count as web links', () {
    expect(isWebLink('https://example.com/a'), isTrue);
    expect(isWebLink('intent://evil'), isFalse);
    expect(isWebLink('file:///sdcard/x'), isFalse);
    expect(isWebLink(null), isFalse);
  });
}
