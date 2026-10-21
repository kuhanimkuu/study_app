import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/api/api_client.dart';
import '../../../core/widgets/sage_mascot.dart';
import 'lesson_screen.dart';

/// "Learn a topic with Sage", plus "Continue: (the lesson)" when one is
/// unfinished (2026-10-21) — on Home and the Practice tab, so learning
/// something new is always one tap away, notes or not.
class LessonEntryCard extends StatefulWidget {
  const LessonEntryCard({super.key, required this.apiClient, this.onLessonClosed});

  final ApiClient apiClient;

  /// After a lesson screen closes (the host can refresh its own numbers).
  final VoidCallback? onLessonClosed;

  @override
  State<LessonEntryCard> createState() => LessonEntryCardState();
}

class LessonEntryCardState extends State<LessonEntryCard> {
  Map<String, dynamic>? _inProgress;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final lessons = await widget.apiClient.listLessons(status: 'in_progress', limit: 1);
      if (mounted) setState(() => _inProgress = lessons.isEmpty ? null : lessons.first);
    } catch (_) {
      // Optional: the card still offers a new lesson.
    }
  }

  Future<void> _open({int? lessonId}) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LessonScreen(apiClient: widget.apiClient, lessonId: lessonId),
    ));
    await reload();
    widget.onLessonClosed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = _inProgress;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => _open(),
            child: Container(
              decoration: const BoxDecoration(gradient: StudyOsColors.brandGradient),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  const SageMascot(size: 52, mood: SageMood.cheer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Learn a topic with Sage', style: theme.textTheme.titleMedium?.copyWith(color: Colors.white)),
                        const SizedBox(height: 2),
                        Text(
                          'A short lesson in steps, with a quick check after each one.',
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_rounded, color: Colors.white),
                ],
              ),
            ),
          ),
          if (current != null)
            ListTile(
              leading: const Icon(Icons.play_circle_fill_rounded, color: StudyOsColors.primary),
              title: Text('Continue: ${current['title']}', maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${current['answered']} of ${current['checks']} checks done'),
              onTap: () => _open(lessonId: current['id'] as int),
            ),
        ],
      ),
    );
  }
}
