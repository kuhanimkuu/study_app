import 'package:flutter/material.dart';

import '../../../../../app/theme.dart';
import '../../../../../core/api/api_client.dart';
import '../../../../../core/widgets/sage_mascot.dart';
import '../../../../../core/widgets/tab_kit.dart';

/// Standalone semantic search within one Knowledge Space's stored
/// material (blueprint Section 13) — a 7th tab on ProjectWorkspaceScreen.
/// Unlike the Chat tab's `/api/ask/project` (which returns a
/// conversational response), this hits the dedicated
/// `GET /api/v1/knowledge-spaces/{slug}/search` endpoint and renders raw
/// ranked results directly — no LLM synthesis, just "here's what matched
/// and how well." Redesigned 2026-10-28 in the Studio tab's style: a big
/// search bar, match-strength bars, and the search words highlighted.
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
  String _searchedFor = '';
  final Set<int> _expanded = {};

  static const _ideas = ['definition', 'formula', 'example', 'causes', 'summary'];

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _search([String? text]) async {
    if (text != null) _queryController.text = text;
    final query = _queryController.text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isSearching = true;
      _error = null;
      _searchedFor = query;
      _expanded.clear();
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

  /// How well a passage matches, in words.
  static ({String label, Color color}) _strength(double score) {
    if (score >= 0.6) return (label: 'Strong match', color: StudyOsColors.success);
    if (score >= 0.4) return (label: 'Good match', color: StudyOsColors.primary);
    return (label: 'Loose match', color: StudyOsColors.amber);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = _results ?? const [];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        const TabIntro(title: 'Search', subtitle: 'Find the exact passage in your sources, word for word.'),
        const SizedBox(height: 14),
        _searchBar(context),
        if (_isSearching) ...[
          const SizedBox(height: 12),
          ClipRRect(borderRadius: BorderRadius.circular(4), child: const LinearProgressIndicator(minHeight: 3)),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 18),
        if (_searchedFor.isEmpty)
          _startHere(context)
        else if (!_isSearching && results.isEmpty && _error == null)
          _noMatches(context)
        else if (results.isNotEmpty) ...[
          Text(
            '${results.length} ${results.length == 1 ? 'passage' : 'passages'} for “$_searchedFor”',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          for (final (i, raw) in results.indexed) ...[
            _resultCard(context, i, raw as Map<String, dynamic>),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }

  Widget _searchBar(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: StudyOsColors.primary.withValues(alpha: 0.35), width: 1.5),
        boxShadow: [BoxShadow(color: StudyOsColors.primary.withValues(alpha: 0.10), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: StudyOsColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _queryController,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'e.g. photosynthesis, Newton\'s 2nd law…',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
              onSubmitted: (_) => _search(),
            ),
          ),
          Material(
            color: StudyOsColors.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _isSearching ? null : _search,
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _startHere(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        const SizedBox(height: 12),
        const SageMascot(size: 84),
        const SizedBox(height: 12),
        Text('What are you looking for?', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          'I search by meaning, not just exact words, and show you the passages that match best.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final idea in _ideas)
              ActionChip(
                avatar: const Icon(Icons.search_rounded, size: 16),
                label: Text(idea),
                onPressed: () => _search(idea),
              ),
          ],
        ),
      ],
    );
  }

  Widget _noMatches(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        const SizedBox(height: 12),
        const SageMascot(size: 76, mood: SageMood.thinking),
        const SizedBox(height: 10),
        Text('Nothing matched “$_searchedFor”', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          'Try a shorter phrase or another word for it. If the topic isn\'t in your sources yet, add it in Sources.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _resultCard(BuildContext context, int index, Map<String, dynamic> result) {
    final theme = Theme.of(context);
    final score = (result['score'] as num).toDouble().clamp(0.0, 1.0);
    final strength = _strength(score);
    final open = _expanded.contains(index);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => setState(() => open ? _expanded.remove(index) : _expanded.add(index)),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconBadge(icon: Icons.format_quote_rounded, color: strength.color, size: 32),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(strength.label, style: theme.textTheme.labelMedium?.copyWith(color: strength.color, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: score,
                            minHeight: 5,
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation(strength.color),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('${(score * 100).round()}%', style: theme.textTheme.labelLarge?.copyWith(color: strength.color, fontWeight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 10),
              Text.rich(
                _highlighted(result['chunk'] as String, _searchedFor, theme),
                maxLines: open ? null : 4,
                overflow: open ? null : TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
              ),
              const SizedBox(height: 6),
              Text(
                open ? 'Tap to show less' : 'Tap to read it all',
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The passage with each searched word (3+ letters) marked.
  static TextSpan _highlighted(String text, String query, ThemeData theme) {
    final words = query
        .toLowerCase()
        .split(RegExp(r'[^\w]+'))
        .where((w) => w.length >= 3)
        .toSet()
        .map(RegExp.escape)
        .toList();
    if (words.isEmpty) return TextSpan(text: text);
    final pattern = RegExp(words.join('|'), caseSensitive: false);
    final mark = TextStyle(
      fontWeight: FontWeight.w800,
      backgroundColor: StudyOsColors.amber.withValues(alpha: theme.brightness == Brightness.dark ? 0.35 : 0.28),
    );
    final spans = <TextSpan>[];
    var last = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      spans.add(TextSpan(text: m.group(0), style: mark));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return TextSpan(children: spans);
  }
}
