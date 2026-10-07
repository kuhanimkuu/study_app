// The real ConceptsListScreen wired to a fake ApiClient (2026-10-07):
// pins that "Generate concepts from material" is offered on an empty
// project, calls the generate endpoint, then reloads so the new concepts
// actually appear — and that the server's actionable error reaches the
// student unchanged.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:study_os_frontend/core/api/api_client.dart';
import 'package:study_os_frontend/features/learning/concepts/presentation/screens/concepts_list_screen.dart';

class _FakeApi extends ApiClient {
  _FakeApi({this.failWith}) : super(baseUrl: 'http://test');

  final ApiException? failWith;
  final List<Map<String, dynamic>> concepts = [];
  int generateCalls = 0;

  @override
  Future<Map<String, dynamic>> listConcepts(String slug) async => {'concepts': List.of(concepts)};

  @override
  Future<Map<String, dynamic>> getConceptMastery(int conceptId) async => {'mastery': 0.0};

  @override
  Future<Map<String, dynamic>> generateConcepts(String slug) async {
    generateCalls++;
    if (failWith != null) throw failWith!;
    final created = [
      {'id': 1, 'name': 'Mitochondria', 'description': 'ATP production'},
      {'id': 2, 'name': 'Osmosis', 'description': 'water movement'},
    ];
    concepts.addAll(created);
    return {'concepts': created, 'skipped_existing': 0};
  }
}

Widget _wrap(ApiClient api) => MaterialApp(home: ConceptsListScreen(apiClient: api, slug: 'cell_bio'));

void main() {
  testWidgets('empty project offers generation, and generated concepts appear', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(_wrap(api));
    await tester.pumpAndSettle();

    expect(find.textContaining('No concepts yet'), findsOneWidget);
    await tester.tap(find.text('Generate concepts from material'));
    await tester.pumpAndSettle();

    expect(api.generateCalls, 1);
    expect(find.text('Added 2 concepts.'), findsOneWidget);
    expect(find.text('Mitochondria'), findsOneWidget);
    expect(find.text('Osmosis'), findsOneWidget);
    // Still offered above a non-empty list, for after more material is added.
    expect(find.text('Generate concepts from material'), findsOneWidget);
  });

  testWidgets("a 503 shows the server's set-up-a-key message", (tester) async {
    final api = _FakeApi(failWith: ApiException(503, "The free AI model isn't available on this server — add your own API key"));
    await tester.pumpWidget(_wrap(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Generate concepts from material'));
    await tester.pumpAndSettle();

    expect(find.textContaining('add your own API key'), findsOneWidget);
    expect(find.textContaining('No concepts yet'), findsOneWidget);
  });
}
