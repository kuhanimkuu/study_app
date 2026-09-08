// Verifies each block widget against REAL block shapes captured from this
// project's own server/README.md end-to-end curl testing (not shapes
// assumed from json.md alone) — this is exactly the kind of check that
// would have caught the interactive_graph nesting bug before it shipped.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:study_os_frontend/features/chat/presentation/widgets/block_view.dart';

const _testBaseUrl = 'http://127.0.0.1:8000';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('text block renders its content', (tester) async {
    await tester.pumpWidget(_wrap(const BlockView(
      block: {'type': 'text', 'content': 'Solving 2x + 3 = 7: ...', 'source': 'moderator'},
      baseUrl: _testBaseUrl,
    )));
    expect(find.textContaining('Solving 2x + 3 = 7'), findsOneWidget);
  });

  testWidgets('equation block renders LaTeX without throwing', (tester) async {
    await tester.pumpWidget(_wrap(const BlockView(
      block: {'type': 'equation', 'latex': 'x = 2', 'source': 'symbolic'},
      baseUrl: _testBaseUrl,
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // The real shape returned by features/moderator/engine.py's graph route:
  // {"type": "interactive_graph", "data": result["points"], "latex": ..., "source": "graphing"}
  // where result["points"] is {"x": [...], "y": [...]} DIRECTLY — not
  // nested under a "points" key inside "data". An earlier version of
  // GraphBlockView assumed the nested shape and would have found nothing
  // to plot; this test pins the real shape so that regression can't
  // silently return.
  testWidgets('graph block renders a LineChart from the real (unnested) moderator shape', (tester) async {
    await tester.pumpWidget(_wrap(const BlockView(
      block: {
        'type': 'interactive_graph',
        'data': {
          'x': [-2.0, -1.0, 0.0, 1.0, 2.0],
          'y': [4.0, 1.0, 0.0, 1.0, 4.0],
        },
        'latex': 'y = x^{2}',
        'source': 'graphing',
      },
      baseUrl: _testBaseUrl,
    )));
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('(graph data missing or malformed)'), findsNothing);
  });

  testWidgets('graph block shows an honest fallback for malformed data', (tester) async {
    await tester.pumpWidget(_wrap(const BlockView(
      block: {'type': 'interactive_graph', 'data': <String, dynamic>{}, 'latex': 'y = x'},
      baseUrl: _testBaseUrl,
    )));
    expect(find.byType(LineChart), findsNothing);
    expect(find.text('(graph data missing or malformed)'), findsOneWidget);
  });

  testWidgets('source block renders content and source label', (tester) async {
    await tester.pumpWidget(_wrap(const BlockView(
      block: {'type': 'source', 'content': 'Entropy is...', 'source': 'searchable_knowledge'},
      baseUrl: _testBaseUrl,
    )));
    expect(find.textContaining('Entropy is'), findsOneWidget);
    expect(find.text('searchable_knowledge'), findsOneWidget);
  });

  testWidgets('clarification block renders the question', (tester) async {
    await tester.pumpWidget(_wrap(const BlockView(
      block: {'type': 'clarification', 'question': "I've read this PDF. What would you like me to do with it?"},
      baseUrl: _testBaseUrl,
    )));
    expect(find.textContaining("What would you like me to do with it"), findsOneWidget);
  });

  testWidgets('error block renders engine and message', (tester) async {
    await tester.pumpWidget(_wrap(const BlockView(
      block: {'type': 'error', 'engine': 'symbolic', 'message': 'could not parse expression'},
      baseUrl: _testBaseUrl,
    )));
    expect(find.textContaining('symbolic'), findsOneWidget);
    expect(find.textContaining('could not parse expression'), findsOneWidget);
  });

  // Real shape from ocr/table_extraction's engine.py output.
  testWidgets('table block renders headers and rows', (tester) async {
    await tester.pumpWidget(_wrap(const BlockView(
      block: {
        'type': 'table',
        'headers': ['Name', 'Value'],
        'rows': [
          ['x', '2'],
          ['y', '3'],
        ],
      },
      baseUrl: _testBaseUrl,
    )));
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('y'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  // Real shape from moderator/engine.py's _route_static_image: "content" is
  // a "/generated/<file>" URL path server/main.py serves via StaticFiles,
  // not inline image data — the widget must combine it with baseUrl.
  testWidgets('static_image block builds the full URL from baseUrl + content', (tester) async {
    await tester.pumpWidget(_wrap(const BlockView(
      block: {'type': 'static_image', 'content': '/generated/abc123.png', 'format': 'png'},
      baseUrl: _testBaseUrl,
    )));
    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as NetworkImage;
    expect(provider.url, '$_testBaseUrl/generated/abc123.png');
  });

  testWidgets('animation block builds the full URL from baseUrl + content', (tester) async {
    await tester.pumpWidget(_wrap(const BlockView(
      block: {'type': 'animation', 'content': '/generated/abc123.gif', 'fps': 2},
      baseUrl: _testBaseUrl,
    )));
    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as NetworkImage;
    expect(provider.url, '$_testBaseUrl/generated/abc123.gif');
  });

  testWidgets('3d block renders a reference card with a real open action, not a fake viewer',
      (tester) async {
    await tester.pumpWidget(_wrap(const BlockView(
      block: {'type': '3d', 'content': '/generated/abc123.glb', 'format': 'glb'},
      baseUrl: _testBaseUrl,
    )));
    expect(find.textContaining('/generated/abc123.glb'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);
  });

  testWidgets('pdf block renders a reference card with a real open action, not a fake viewer',
      (tester) async {
    await tester.pumpWidget(_wrap(const BlockView(
      block: {'type': 'pdf', 'content': '/generated/abc123.pdf', 'doc_type': 'study_guide'},
      baseUrl: _testBaseUrl,
    )));
    expect(find.textContaining('study_guide'), findsOneWidget);
    expect(find.textContaining('/generated/abc123.pdf'), findsOneWidget);
    // No inline PDF preview (still not a fake viewer), but a real action
    // to open the file externally — see PdfBlockView's doc comment.
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);
  });

  testWidgets('unknown block type falls back to a visible, labelled dump', (tester) async {
    await tester.pumpWidget(_wrap(const BlockView(
      block: {'type': 'quiz', 'question': 'not yet supported'},
      baseUrl: _testBaseUrl,
    )));
    expect(find.textContaining('"quiz"'), findsOneWidget);
    expect(find.textContaining("isn't rendered yet"), findsOneWidget);
  });
}
