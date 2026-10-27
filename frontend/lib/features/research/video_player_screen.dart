import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../chat/presentation/widgets/blocks/links_block.dart' show openWebLink;

/// Watch a YouTube video inside the app (2026-10-27) with YouTube's own
/// embedded player — nothing is downloaded. It starts at the section worth
/// watching (`start`), says what that part covers, and lists the chapters
/// so the student can jump around. "Watch on YouTube" opens the original.
///
/// [video] is a video item's fields: id, title, url, channel, start, end,
/// section, covers, chapters, attribution (server/domains/research).
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key, required this.video});

  final Map<String, dynamic> video;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

String clockLabel(int seconds) {
  final h = seconds ~/ 3600, m = seconds % 3600 ~/ 60, s = seconds % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

/// "Watch 1:35–6:40" for a section, or "Starts at 1:35".
String? sectionLabel(Map<String, dynamic> video) {
  final start = (video['start'] as num?)?.toInt() ?? 0;
  final end = (video['end'] as num?)?.toInt();
  if (end != null) return 'Watch ${clockLabel(start)}–${clockLabel(end)}';
  if (start > 0) return 'Starts at ${clockLabel(start)}';
  return null;
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final YoutubePlayerController _controller = YoutubePlayerController.fromVideoId(
    videoId: widget.video['id'] as String,
    autoPlay: true,
    startSeconds: ((widget.video['start'] as num?) ?? 0).toDouble(),
    params: const YoutubePlayerParams(showFullscreenButton: true, strictRelatedVideos: true, showVideoAnnotations: false),
  );

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final video = widget.video;
    final chapters = (video['chapters'] as List? ?? const []).cast<Map>();
    final label = sectionLabel(video);
    return Scaffold(
      appBar: AppBar(title: Text(video['title'] as String? ?? 'Video', maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: SafeArea(
        child: ListView(
          children: [
            YoutubePlayer(controller: _controller),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(video['title'] as String? ?? '', style: theme.textTheme.titleMedium),
                  if (video['channel'] != null)
                    Text(video['channel'] as String, style: theme.textTheme.bodySmall),
                  if (label != null || video['section'] != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.play_circle_outline_rounded, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  [label, if (video['section'] != null) '“${video['section']}”'].whereType<String>().join(' · '),
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                            ],
                          ),
                          if (video['covers'] != null) ...[
                            const SizedBox(height: 6),
                            Text(video['covers'] as String, style: theme.textTheme.bodyMedium),
                          ],
                        ],
                      ),
                    ),
                  ] else if (video['covers'] != null) ...[
                    const SizedBox(height: 8),
                    Text(video['covers'] as String, style: theme.textTheme.bodyMedium),
                  ],
                  if (chapters.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Chapters', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    for (final chapter in chapters)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Text(clockLabel((chapter['start'] as num).toInt()), style: theme.textTheme.labelLarge),
                        title: Text(chapter['title'] as String),
                        selected: (chapter['start'] as num).toInt() == ((video['start'] as num?) ?? 0).toInt(),
                        onTap: () => _controller.seekTo(seconds: (chapter['start'] as num).toDouble(), allowSeekAhead: true),
                      ),
                  ],
                  const SizedBox(height: 12),
                  if (video['attribution'] != null)
                    Text(video['attribution'] as String, style: theme.textTheme.labelSmall),
                  TextButton.icon(
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Watch on YouTube'),
                    onPressed: () => openWebLink(context, video['url'] as String? ?? 'https://www.youtube.com/watch?v=${video['id']}'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
