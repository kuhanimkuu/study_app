import 'package:flutter/material.dart';

import '../../../../../core/api/api_client.dart';

/// Standalone semantic search within one Knowledge Space's stored
/// material (blueprint Section 13) — a new 7th tab on
/// ProjectWorkspaceScreen. Unlike the Chat tab's `/api/ask/project` (which
/// returns a conversational response), this hits the dedicated
/// `GET /api/v1/knowledge-spaces/{slug}/search` endpoint and renders raw
/// ranked results directly — no LLM synthesis, just "here's what matched
/// and how well."
class KnowledgeSearchScreen extends StatefulWidget {
  const KnowledgeSearchScreen({super.key, required this.apiClient, required this.slug});

  final ApiClient apiClient;
  final String slug;

  @override
  State<KnowledgeSearchScreen> createState() => _KnowledgeSearchScreenState();
}

class _KnowledgeSearchScreenState extends State<KnowledgeSearchScreen> {
  final _queryController = TextEditingController();
  List<dynamic>? _results;
  bool _isSearching = false;
  String? _error;
  bool _searched = false;

  Future<void> _search() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _isSearching = true;
      _error = null;
      _searched = true;
    });
    try {
      final result = await widget.apiClient.searchKnowledgeSpace(slug: widget.slug, query: query);
      setState(() => _results = result['results'] as List<dynamic>);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _queryController,
                  decoration: const InputDecoration(
                    hintText: 'Search this project\'s material...',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.search), onPressed: _isSearching ? null : _search),
            ],
          ),
        ),
        if (_isSearching) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        Expanded(
          child: Builder(
            builder: (context) {
              if (!_searched) {
                return const Center(child: Text('Search this project\'s uploaded material.'));
              }
              final results = _results ?? [];
              if (!_isSearching && results.isEmpty && _error == null) {
                return const Center(child: Text('No matching material found.'));
              }
              return ListView.builder(
                itemCount: results.length,
                itemBuilder: (context, index) {
                  final result = results[index] as Map<String, dynamic>;
                  final score = (result['score'] as num).toDouble();
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: ListTile(
                      title: Text(result['chunk'] as String, maxLines: 4, overflow: TextOverflow.ellipsis),
                      trailing: Text('${(score * 100).round()}%', style: Theme.of(context).textTheme.labelSmall),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
