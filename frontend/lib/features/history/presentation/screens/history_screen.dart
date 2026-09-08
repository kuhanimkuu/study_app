import 'package:flutter/material.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/storage/local_db.dart';
import '../../../chat/presentation/widgets/block_view.dart';

/// Personal activity history. Local-first pivot: the events themselves
/// live only in LocalDb (see server/main.py's architecture note) — this
/// screen reads them from the device, then reuses the moderator's own
/// memory_query route (via /api/ask/text, task: "memory_query") to answer
/// natural-language queries like "what did I struggle with yesterday"
/// against that local data, sent along per-request as `local_events`
/// rather than duplicating query_memory's date/struggle-matching logic in
/// Dart. Results render through the same BlockView the chat screen uses.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _queryController = TextEditingController(text: 'everything');
  List<dynamic>? _blocks;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final events = await LocalDb.instance.loadActivityForQuery();
      final result = await widget.apiClient.askText(
        content: _queryController.text.trim(),
        task: 'memory_query',
        localEvents: events,
        sessionId: 'history',
      );
      setState(() => _blocks = result['blocks'] as List<dynamic>? ?? []);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryController,
                    decoration: const InputDecoration(
                      hintText: 'e.g. "what did I struggle with yesterday"',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(icon: const Icon(Icons.search), onPressed: _load),
              ],
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: (_blocks == null || _blocks!.isEmpty)
                ? const Center(child: Text('No matching activity yet.'))
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      for (final block in _blocks!)
                        BlockView(block: block as Map<String, dynamic>, baseUrl: widget.apiClient.baseUrl),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
