import 'package:flutter/material.dart';

import '../../../../../core/api/api_client.dart';
import '../../../../../core/errors/error_presentation.dart';
import '../../../../../core/widgets/async_list_view.dart';
import '../../../../../core/widgets/list_item_card.dart';
import 'note_editor_screen.dart';

/// Student-authored notes within a Knowledge Space (blueprint Section 14)
/// — a new 6th tab on ProjectWorkspaceScreen.
class NotesListScreen extends StatefulWidget {
  const NotesListScreen({super.key, required this.apiClient, required this.slug});

  final ApiClient apiClient;
  final String slug;

  @override
  State<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends State<NotesListScreen> {
  List<Map<String, dynamic>>? _notes;
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
      final result = await widget.apiClient.listNotes(widget.slug);
      setState(() => _notes = (result['notes'] as List<dynamic>).cast<Map<String, dynamic>>());
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createNote() async {
    try {
      final created = await widget.apiClient.createNote(slug: widget.slug, title: 'Untitled note');
      await _load();
      if (mounted) await _openNote(created);
    } on ApiException catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _openNote(Map<String, dynamic> note) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => NoteEditorScreen(apiClient: widget.apiClient, note: note)),
    );
    _load();
  }

  Future<void> _deleteNote(int id) async {
    try {
      await widget.apiClient.deleteNote(id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(onPressed: _createNote, child: const Icon(Icons.add)),
      body: AsyncListView<Map<String, dynamic>>(
        isLoading: _isLoading,
        error: _error,
        items: _notes,
        onRefresh: _load,
        emptyMessage: 'No notes yet. Tap + to add one.',
        emptyIcon: Icons.note_alt_outlined,
        itemBuilder: (context, note) {
          final body = note['body'] as String;
          final wordCount = body.trim().isEmpty ? 0 : body.trim().split(RegExp(r'\s+')).length;
          return ListItemCard(
            icon: Icons.notes_outlined,
            iconColor: Theme.of(context).colorScheme.secondary,
            title: note['title'] as String,
            subtitle: body.isEmpty ? 'Empty note' : '$body\n$wordCount word${wordCount == 1 ? '' : 's'}',
            subtitleMaxLines: 3,
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _deleteNote(note['id'] as int),
            ),
            onTap: () => _openNote(note),
          );
        },
      ),
    );
  }
}
