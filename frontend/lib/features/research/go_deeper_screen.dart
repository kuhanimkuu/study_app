import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/widgets/sage_mascot.dart';
import '../chat/presentation/widgets/blocks/links_block.dart' show openWebLink;
import 'video_card.dart';

/// Go deeper (2026-10-27): two or three real videos, articles, books or
/// papers on a topic, chosen by Sage from what the server found through
/// the providers' official APIs — never links the AI made up. Videos play
/// in the app at the section worth watching. Every source can be reported.
class GoDeeperScreen extends StatefulWidget {
  const GoDeeperScreen({super.key, required this.apiClient, required this.topic, this.context, this.depth});

  final ApiClient apiClient;
  final String topic;

  /// What the student was just studying, so picks fit it.
  final String? context;
  final String? depth;

  @override
  State<GoDeeperScreen> createState() => _GoDeeperScreenState();
}

class _GoDeeperScreenState extends State<GoDeeperScreen> {
  List<Map<String, dynamic>>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _items = null;
      _error = null;
    });
    try {
      final result = await widget.apiClient.goDeeper(topic: widget.topic, context: widget.context, depth: widget.depth);
      if (mounted) setState(() => _items = (result['items'] as List).cast<Map<String, dynamic>>());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _report(Map<String, dynamic> item) async {
    final reason = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Report this source'),
        content: TextField(
          controller: reason,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'What’s wrong? e.g. pirated copy, wrong, broken, inappropriate'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Report')),
        ],
      ),
    );
    if (send != true || reason.text.trim().length < 3 || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await widget.apiClient.reportSource(url: item['url'] as String, reason: reason.text.trim());
      messenger.showSnackBar(SnackBar(content: Text(result['message'] as String? ?? 'Reported.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: Text('Go deeper: ${widget.topic}', maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: SafeArea(
        child: _error != null
            ? ListView(padding: const EdgeInsets.all(24), children: [
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _load, child: const Text('Try again')),
              ])
            : items == null
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const SageMascot(size: 96, mood: SageMood.thinking),
                      const SizedBox(height: 12),
                      Text('Finding good videos, books and papers…', style: theme.textTheme.titleSmall),
                    ]),
                  )
                : items.isEmpty
                    ? ListView(padding: const EdgeInsets.all(24), children: const [
                        Text('Nothing good turned up for this right now. Try a more specific topic.'),
                      ])
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Text('Picked for you from real sources', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 8),
                          for (final item in items) _SourceCard(item: item, onReport: () => _report(item)),
                        ],
                      ),
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.item, required this.onReport});

  final Map<String, dynamic> item;
  final VoidCallback onReport;

  static const _icons = {
    'article': Icons.article_outlined,
    'book': Icons.menu_book_outlined,
    'paper': Icons.science_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final video = item['video'] as Map<String, dynamic>?;
    final report = Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        icon: const Icon(Icons.flag_outlined, size: 16),
        label: const Text('Report'),
        onPressed: onReport,
      ),
    );
    if (video != null) {
      return Column(children: [
        VideoCard(
          video: {...video, 'title': item['title'], 'url': item['url'], 'attribution': item['attribution']},
          reason: item['reason'] as String?,
        ),
        report,
      ]);
    }
    final authors = (item['authors'] as List?)?.cast<String>() ?? const [];
    final byline = [if (authors.isNotEmpty) authors.join(', '), if (item['year'] != null) '${item['year']}'].join(' · ');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_icons[item['kind']] ?? Icons.link_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item['title'] as String, style: theme.textTheme.titleSmall),
                    if (byline.isNotEmpty) Text(byline, style: theme.textTheme.bodySmall),
                  ]),
                ),
              ],
            ),
            if (item['reason'] != null) ...[
              const SizedBox(height: 6),
              Text(item['reason'] as String, style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
            ],
            // Tier A only: a short excerpt, with its credit and licence.
            if (item['excerpt'] != null) ...[
              const SizedBox(height: 6),
              Text(item['excerpt'] as String, style: theme.textTheme.bodySmall),
            ] else if ((item['description'] as String?)?.isNotEmpty ?? false) ...[
              const SizedBox(height: 6),
              Text(item['description'] as String, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 6),
            Text(
              [item['attribution'], if (item['licence'] != null) 'Licence: ${item['licence']}'].whereType<String>().join(' · '),
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(item['kind'] == 'book' ? 'Find this book' : 'Open'),
                  onPressed: () => openWebLink(context, item['url'] as String),
                ),
                const Spacer(),
                report,
              ],
            ),
          ],
        ),
      ),
    );
  }
}
