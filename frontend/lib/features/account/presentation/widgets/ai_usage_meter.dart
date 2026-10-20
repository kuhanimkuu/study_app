import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';

/// The token meter (2026-10-20): how many AI tokens this student has used
/// and roughly what they cost. Read from the server's own log of provider
/// calls (billing/router.py's ai_usage_summary) — only ever this student's
/// rows, and no API key is involved in showing it.
///
/// Prices are an estimate for BYOK keys: the provider bills the student
/// directly and Study OS never sees that bill. Hosted-tier calls show what
/// the wallet actually paid.

/// "1,234" → "1.2K", millions → "3.4M".
String formatTokens(int tokens) {
  if (tokens < 1000) return '$tokens';
  if (tokens < 1000000) return '${(tokens / 1000).toStringAsFixed(tokens < 10000 ? 1 : 0)}K';
  return '${(tokens / 1000000).toStringAsFixed(1)}M';
}

/// Micro-USD → "$0.0042" below a cent (so a cheap call isn't shown as
/// free), "$1.23" from a cent up.
String formatMicroUsd(int micro) {
  if (micro == 0) return '\$0.00';
  final usd = micro / 1000000;
  return usd < 0.01 ? '\$${usd.toStringAsFixed(4)}' : '\$${usd.toStringAsFixed(2)}';
}

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

/// Profile → "AI usage": this month's tokens and estimated cost at a
/// glance; tap for the full breakdown.
class AiUsageMeterCard extends StatefulWidget {
  const AiUsageMeterCard({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  State<AiUsageMeterCard> createState() => _AiUsageMeterCardState();
}

class _AiUsageMeterCardState extends State<AiUsageMeterCard> {
  Map<String, dynamic>? _usage;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final usage = await widget.apiClient.getAiUsage();
      if (mounted) setState(() => _usage = usage);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final month = _usage?['last_30_days'] as Map<String, dynamic>?;
    final tokens = _int(month?['input_tokens']) + _int(month?['output_tokens']);

    final String summary;
    if (_failed) {
      summary = 'Couldn\'t load your usage right now';
    } else if (month == null) {
      summary = 'Loading…';
    } else if (_int(month['calls']) == 0) {
      summary = 'No AI calls in the last 30 days';
    } else {
      summary = '${formatTokens(tokens)} tokens · about ${formatMicroUsd(_int(month['cost_micro_usd']))} in the last 30 days';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => AiUsageScreen(apiClient: widget.apiClient)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: StudyOsColors.xp, borderRadius: BorderRadius.circular(11)),
                child: const Icon(Icons.speed_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI usage', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(summary, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// The full meter: today / last 30 days / all time, then each model used.
class AiUsageScreen extends StatefulWidget {
  const AiUsageScreen({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  State<AiUsageScreen> createState() => _AiUsageScreenState();
}

class _AiUsageScreenState extends State<AiUsageScreen> {
  Map<String, dynamic>? _usage;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final usage = await widget.apiClient.getAiUsage();
      if (mounted) setState(() => _usage = usage);
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : 'Couldn\'t reach the server.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usage = _usage;

    Widget body;
    if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    } else if (usage == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final models = (usage['by_model'] as List? ?? const []).cast<Map<String, dynamic>>();
      final unpriced = _int((usage['all_time'] as Map?)?['unpriced_calls']);
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Row(
              children: [
                Expanded(child: _PeriodTile(label: 'Today', data: usage['today'] as Map<String, dynamic>)),
                const SizedBox(width: 8),
                Expanded(child: _PeriodTile(label: 'Last 30 days', data: usage['last_30_days'] as Map<String, dynamic>)),
                const SizedBox(width: 8),
                Expanded(child: _PeriodTile(label: 'All time', data: usage['all_time'] as Map<String, dynamic>)),
              ],
            ),
            const SizedBox(height: 20),
            Text('BY MODEL', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, letterSpacing: 1)),
            const SizedBox(height: 8),
            if (models.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Nothing yet. Usage shows up here after you chat, generate or get answers graded with your own API key or the hosted tier. The free on-device model doesn\'t count.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            for (final m in models) _ModelRow(data: m),
            const SizedBox(height: 20),
            _Disclaimer(unpricedCalls: unpriced),
          ],
        ),
      );
    }

    return Scaffold(appBar: AppBar(title: const Text('AI usage')), body: body);
  }
}

class _PeriodTile extends StatelessWidget {
  const _PeriodTile({required this.label, required this.data});

  final String label;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = _int(data['input_tokens']) + _int(data['output_tokens']);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outline, width: 1.5),
      ),
      child: Column(
        children: [
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Text(formatTokens(tokens), style: theme.textTheme.titleLarge),
          Text('tokens', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Text(
            '≈ ${formatMicroUsd(_int(data['cost_micro_usd']))}',
            style: theme.textTheme.titleSmall?.copyWith(color: StudyOsColors.xp),
          ),
        ],
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final input = _int(data['input_tokens']);
    final output = _int(data['output_tokens']);
    final cost = data['cost_micro_usd'] as num?;
    final hosted = data['hosted'] == true;
    final calls = _int(data['calls']);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${data['model_name']}', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    '${data['provider']} · ${hosted ? 'hosted' : 'your key'} · $calls ${calls == 1 ? 'call' : 'calls'}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${formatTokens(input)} in · ${formatTokens(output)} out',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Text(
              cost == null ? 'no price' : '≈ ${formatMicroUsd(cost.toInt())}',
              style: theme.textTheme.titleSmall?.copyWith(
                color: cost == null ? theme.colorScheme.onSurfaceVariant : StudyOsColors.xp,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer({required this.unpricedCalls});

  final int unpricedCalls;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text('Prices are estimates', style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'With your own API key, your provider bills you directly — these prices come from their public price list, '
            'so check your provider\'s dashboard for the exact amount. Hosted-tier calls show what your wallet paid.',
            style: style,
          ),
          if (unpricedCalls > 0) ...[
            const SizedBox(height: 6),
            Text(
              '$unpricedCalls ${unpricedCalls == 1 ? 'call used a model' : 'calls used models'} we don\'t have a price for, '
              'so ${unpricedCalls == 1 ? 'it isn\'t' : 'they aren\'t'} in the totals.',
              style: style,
            ),
          ],
          const SizedBox(height: 6),
          Text('Only you can see this. Your API key is never shown or used here.', style: style),
        ],
      ),
    );
  }
}
