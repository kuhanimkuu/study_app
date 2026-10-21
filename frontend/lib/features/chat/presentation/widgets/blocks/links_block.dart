import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Renders `{"type": "links", "title": "Learn more", "links": [{"label", "url"}]}`
/// — the project chat's card of places to read more (2026-10-21). The
/// server only sends real links (search pages on learning sites, live web
/// results); each opens in the phone's browser.
class LinksBlockView extends StatelessWidget {
  const LinksBlockView({super.key, required this.block});

  final Map<String, dynamic> block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final links = (block['links'] as List? ?? const [])
        .whereType<Map>()
        .where((l) => isWebLink(l['url']?.toString()))
        .toList();
    if (links.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.travel_explore_rounded, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(block['title']?.toString() ?? 'Learn more', style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 4),
          for (final link in links)
            LinkRow(label: link['label']?.toString() ?? link['url'].toString(), url: link['url'].toString()),
        ],
      ),
    );
  }
}

/// Only http(s) links are ever opened — never another scheme a crafted
/// web result could carry.
bool isWebLink(String? url) {
  final uri = url == null ? null : Uri.tryParse(url);
  return uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty;
}

Future<void> openWebLink(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final opened = isWebLink(url) && await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!opened) messenger?.showSnackBar(const SnackBar(content: Text("Couldn't open that link.")));
}

class LinkRow extends StatelessWidget {
  const LinkRow({super.key, required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => openWebLink(context, url),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
                  Text(
                    Uri.parse(url).host.replaceFirst('www.', ''),
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.open_in_new_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
