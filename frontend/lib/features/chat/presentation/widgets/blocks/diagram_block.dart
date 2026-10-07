import 'package:flutter/material.dart';

import '../../../../../app/theme.dart' show monoTextStyle;

/// Renders a `{"type": "diagram", "kind", "elements": [{id, label, x, y}],
/// "relationships": [[from, to], ...]}` block from visual_explanation/
/// diagrams. Until 2026-10-06 no widget existed for this type and it fell
/// through to UnknownBlockView (a raw JSON dump).
///
/// The engine's x/y grid (4 per row, 150px apart) is laid out for a wide
/// canvas and is ignored here: on a phone, a sequential chain — what the
/// moderator's free-text diagram route always produces — reads best as a
/// vertical flow of numbered steps, with a loop marker when the chain
/// closes back on itself (a cycle). Any other relationship shape is shown
/// honestly as the node list plus an explicit list of its connections,
/// rather than pretending it's a chain.
class DiagramBlockView extends StatelessWidget {
  const DiagramBlockView({super.key, required this.block});

  final Map<String, dynamic> block;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final elements = (block['elements'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final edges = (block['relationships'] as List? ?? const [])
        .whereType<List>()
        .where((r) => r.length == 2 && r[0] is int && r[1] is int)
        .map((r) => (r[0] as int, r[1] as int))
        .toList();
    final kind = block['kind']?.toString() ?? 'diagram';
    final labelById = {for (final e in elements) e['id']: e['label']?.toString() ?? ''};

    final n = elements.length;
    final chain = {for (var i = 0; i < n - 1; i++) (i, i + 1)};
    final edgeSet = edges.toSet();
    final isChain = n > 1 && edgeSet.containsAll(chain);
    final closesLoop = isChain && edgeSet.contains((n - 1, 0));
    final isPlainChainOrCycle = isChain && edgeSet.length == chain.length + (closesLoop ? 1 : 0);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(closesLoop ? Icons.loop_rounded : Icons.account_tree_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  '${kind[0].toUpperCase()}${kind.substring(1)} diagram',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (isPlainChainOrCycle) ...[
              for (var i = 0; i < n; i++) ...[
                _Node(index: i + 1, label: elements[i]['label']?.toString() ?? ''),
                if (i < n - 1) _Arrow(color: scheme.primary),
              ],
              if (closesLoop)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.replay_rounded, size: 16, color: scheme.primary),
                      const SizedBox(width: 6),
                      Text('Back to step 1 — the cycle repeats',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.primary)),
                    ],
                  ),
                ),
            ] else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < n; i++) _Node(index: i + 1, label: elements[i]['label']?.toString() ?? '', compact: true),
                ],
              ),
              if (edges.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Connections', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                for (final (a, b) in edges)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('${labelById[a] ?? a}  →  ${labelById[b] ?? b}'),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _Node extends StatelessWidget {
  const _Node({required this.index, required this.label, this.compact = false});

  final int index;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: scheme.primary,
            child: Text('$index', style: monoTextStyle(context, fontSize: 12, color: scheme.onPrimary)),
          ),
          const SizedBox(width: 10),
          Flexible(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Icon(Icons.arrow_downward_rounded, size: 20, color: color.withValues(alpha: 0.7)),
    );
  }
}
