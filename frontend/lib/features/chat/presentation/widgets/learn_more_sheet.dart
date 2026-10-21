import 'package:flutter/material.dart';

import '../../../../core/api/api_client.dart';
import '../../../tutor/lessons/lesson_screen.dart';
import '../../models/chat_message.dart';
import '../../../account/ai_setup/ai_setup.dart';

/// "Learn more from this" under one of Sage's replies (2026-10-21): turn a
/// chat answer into learning — a lesson on it, a quiz in the chat, or
/// flashcards in a subject's review queue.
Future<void> showLearnMoreSheet(
  BuildContext context, {
  required ApiClient apiClient,
  required ChatMessage reply,
  required String? question,
  required VoidCallback onQuizMe,
  String? subjectSlug,
}) {
  final topic = _topicFrom(question, reply);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.school_rounded),
            title: const Text('Teach me this as a lesson'),
            subtitle: Text('Short steps on “$topic”, with checks', maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () {
              Navigator.of(sheetContext).pop();
              // LessonScreen asks for the AI setup itself if needed.
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => LessonScreen(apiClient: apiClient, topic: topic, subjectSlug: subjectSlug),
              ));
            },
          ),
          ListTile(
            leading: const Icon(Icons.quiz_rounded),
            title: const Text('Quiz me on this'),
            subtitle: const Text('Sage asks you questions here, one at a time'),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              if (await AiSetup.ensure(context)) onQuizMe();
            },
          ),
          ListTile(
            leading: const Icon(Icons.style_rounded),
            title: const Text('Save as flashcards'),
            subtitle: const Text('The key facts go into your reviews'),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              if (await AiSetup.ensure(context) && context.mounted) _saveAsFlashcards(context, apiClient, reply, subjectSlug);
            },
          ),
        ],
      ),
    ),
  );
}

/// The lesson topic: the student's question, else the start of the reply.
String _topicFrom(String? question, ChatMessage reply) {
  final source = (question != null && question.trim().isNotEmpty) ? question : reply.plainText;
  final oneLine = source.replaceAll(RegExp(r'\s+'), ' ').trim();
  return oneLine.length > 120 ? '${oneLine.substring(0, 117)}…' : oneLine;
}

const _myLessons = 'My lessons';

Future<void> _saveAsFlashcards(BuildContext context, ApiClient api, ChatMessage reply, String? subjectSlug) async {
  final messenger = ScaffoldMessenger.of(context);
  var slug = subjectSlug;
  if (slug == null) {
    slug = await _pickSubject(context, api);
    if (slug == null) return;
  }
  messenger.showSnackBar(const SnackBar(content: Text('Making flashcards…'), duration: Duration(seconds: 20)));
  try {
    final result = await api.flashcardsFromText(subjectSlug: slug, text: reply.plainText);
    final added = (result['flashcards'] as List).length;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(added == 0
            ? 'Those cards are already in your deck.'
            : '$added flashcard${added == 1 ? '' : 's'} added — they’ll come up in your reviews.'),
      ));
  } on ApiException catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// Which subject the cards go in; "My lessons" is created if needed.
Future<String?> _pickSubject(BuildContext context, ApiClient api) async {
  List<Map<String, dynamic>> subjects = [];
  try {
    subjects = ((await api.listProjects())['projects'] as List).cast<Map<String, dynamic>>();
  } catch (_) {}
  if (!context.mounted) return null;
  final hasMyLessons = subjects.any((s) => s['display_name'] == _myLessons);
  final picked = await showDialog<String>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text('Save flashcards in'),
      children: [
        for (final subject in subjects)
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(subject['slug'] as String),
            child: Text(subject['display_name'] as String),
          ),
        if (!hasMyLessons)
          SimpleDialogOption(onPressed: () => Navigator.of(dialogContext).pop(''), child: const Text(_myLessons)),
      ],
    ),
  );
  if (picked == null || picked.isNotEmpty) return picked;
  try {
    final created = await api.createProject(displayName: _myLessons);
    return created['slug'] as String;
  } on ApiException catch (e) {
    if (e.statusCode == 409) return 'my_lessons';
    rethrow;
  }
}
