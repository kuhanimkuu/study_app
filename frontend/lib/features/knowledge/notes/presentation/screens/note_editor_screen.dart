import 'package:flutter/material.dart';

import '../../../../../core/api/api_client.dart';

/// Edits a single Note's title/body. Explicit "Save" action, matching this
/// app's convention elsewhere (account_screen's "Save profile", etc.) —
/// no autosave-as-you-type.
class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({super.key, required this.apiClient, required this.note});

  final ApiClient apiClient;
  final Map<String, dynamic> note;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final _titleController = TextEditingController(text: widget.note['title'] as String);
  late final _bodyController = TextEditingController(text: widget.note['body'] as String);
  bool _isSaving = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await widget.apiClient.updateNote(
        noteId: widget.note['id'] as int,
        title: _titleController.text.trim().isEmpty ? 'Untitled note' : _titleController.text.trim(),
        body: _bodyController.text,
      );
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Note'),
        actions: [
          IconButton(
            icon: _isSaving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            tooltip: 'Save',
            onPressed: _isSaving ? null : _save,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleController,
              style: Theme.of(context).textTheme.titleLarge,
              decoration: const InputDecoration(hintText: 'Title', border: InputBorder.none),
            ),
            const Divider(height: 16),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: TextField(
                controller: _bodyController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(hintText: 'Write your notes here...', border: InputBorder.none),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
