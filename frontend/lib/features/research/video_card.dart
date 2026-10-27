import 'package:flutter/material.dart';

import 'video_player_screen.dart';

/// A video to watch in the app: thumbnail, title, the section worth
/// watching and what it covers. Tapping opens [VideoPlayerScreen]. Used for
/// a chat's `video` block and Go deeper's video picks.
class VideoCard extends StatelessWidget {
  const VideoCard({super.key, required this.video, this.reason});

  /// id, title, url, channel, start, end, section, covers, chapters, attribution.
  final Map<String, dynamic> video;

  /// Go deeper's one line on why this helps.
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = sectionLabel(video);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoPlayerScreen(video: video))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    'https://i.ytimg.com/vi/${video['id']}/hqdefault.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
                  ),
                  const Center(child: Icon(Icons.play_circle_fill_rounded, size: 64, color: Colors.white)),
                  if (label != null)
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(6)),
                        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(video['title'] as String? ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                  if (video['channel'] != null) Text(video['channel'] as String, style: theme.textTheme.bodySmall),
                  if (video['section'] != null) ...[
                    const SizedBox(height: 6),
                    Text('Section: ${video['section']}', style: theme.textTheme.labelLarge),
                  ],
                  if (video['covers'] != null) ...[
                    const SizedBox(height: 2),
                    Text(video['covers'] as String, style: theme.textTheme.bodyMedium),
                  ],
                  if (reason != null) ...[
                    const SizedBox(height: 4),
                    Text(reason!, style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
