import 'package:flutter/material.dart';

import '../../../../../core/api/api_client.dart';
import '../../../../../core/errors/error_presentation.dart';
import '../../../../../core/widgets/async_list_view.dart';
import '../../../../../core/widgets/list_item_card.dart';
import 'flashcard_review_screen.dart';

/// Flashcards within one Knowledge Space (blueprint Sections 17, 27) — a
/// new 5th tab on ProjectWorkspaceScreen, same placement reasoning as
/// ConceptsListScreen's 4th tab.
class FlashcardsListScreen extends StatefulWidget {
  const FlashcardsListScreen({super.key, required this.apiClient, required this.slug});

  final ApiClient apiClient;
  final String slug;

  @override
  State<FlashcardsListScreen> createState() => _FlashcardsListScreenState();
}

class _FlashcardsListScreenState extends State<FlashcardsListScreen> {
  List<Map<String, dynamic>>? _flashcards;
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
      final result = await widget.apiClient.listFlashcards(widget.slug);
      setState(() => _flashcards = (result['flashcards'] as List<dynamic>).cast<Map<String, dynamic>>());
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createFlashcard() async {
    final frontController = TextEditingController();
    final backController = TextEditingController();
    final create = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New flashcard'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: frontController,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Front', hintText: 'Question or prompt'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: backController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Back', hintText: 'Answer'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Create')),
        ],
      ),
    );
    if (create != true || frontController.text.trim().isEmpty || backController.text.trim().isEmpty) return;

    try {
      await widget.apiClient.createFlashcard(
        slug: widget.slug,
        front: frontController.text.trim(),
        back: backController.text.trim(),
      );
      await _load();
    } on ApiException catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _deleteFlashcard(int id) async {
    try {
      await widget.apiClient.deleteFlashcard(id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _review() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FlashcardReviewScreen(apiClient: widget.apiClient, knowledgeSpaceSlug: widget.slug),
      ),
    );
    _load(); // due dates may have changed while reviewing
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(onPressed: _createFlashcard, child: const Icon(Icons.add)),
      body: AsyncListView<Map<String, dynamic>>(
        isLoading: _isLoading,
        error: _error,
        items: _flashcards,
        onRefresh: _load,
        emptyMessage: 'No flashcards yet. Tap + to add one.',
        emptyIcon: Icons.style_outlined,
        header: Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            onPressed: (_flashcards ?? []).isEmpty ? null : _review,
            icon: const Icon(Icons.style_outlined),
            label: const Text('Review due cards'),
          ),
        ),
        itemBuilder: (context, flashcard) => ListItemCard(
          icon: Icons.style_outlined,
          title: flashcard['front'] as String,
          subtitle: flashcard['back'] as String,
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _deleteFlashcard(flashcard['id'] as int),
          ),
        ),
      ),
    );
  }
}
