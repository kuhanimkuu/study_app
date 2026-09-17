import 'package:flutter/material.dart';

import '../../../../../core/api/api_client.dart';

/// A due-card review queue: show front, reveal back, rate recall on the
/// full FSRS scale (Again/Hard/Good/Easy — see server/domains/learning/
/// flashcard_scheduler.py's docstring for why flashcards use all 4 values
/// while quiz questions only use 2), then move to the next due card.
///
/// `knowledgeSpaceSlug` is optional — when null, this reviews across every
/// Knowledge Space (same account-wide-by-default convention as GET
/// /api/v1/mastery and the Planner's default plan).
class FlashcardReviewScreen extends StatefulWidget {
  const FlashcardReviewScreen({super.key, required this.apiClient, this.knowledgeSpaceSlug});

  final ApiClient apiClient;
  final String? knowledgeSpaceSlug;

  @override
  State<FlashcardReviewScreen> createState() => _FlashcardReviewScreenState();
}

class _FlashcardReviewScreenState extends State<FlashcardReviewScreen> {
  List<Map<String, dynamic>> _queue = [];
  bool _isLoading = true;
  bool _isRevealed = false;
  bool _isSubmitting = false;
  String? _error;
  int _reviewedCount = 0;

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
      final result = await widget.apiClient.getDueFlashcards(knowledgeSpaceSlug: widget.knowledgeSpaceSlug);
      final flashcards = (result['flashcards'] as List<dynamic>).cast<Map<String, dynamic>>();
      setState(() {
        _queue = flashcards;
        _isRevealed = false;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _rate(String rating) async {
    if (_queue.isEmpty) return;
    setState(() => _isSubmitting = true);
    try {
      await widget.apiClient.reviewFlashcard(flashcardId: _queue.first['id'] as int, rating: rating);
      setState(() {
        _queue.removeAt(0);
        _isRevealed = false;
        _reviewedCount++;
      });
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review')),
      body: Builder(
        builder: (context) {
          if (_isLoading) return const Center(child: CircularProgressIndicator());
          if (_error != null) {
            return Center(child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)));
          }
          if (_queue.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_outline, size: 48),
                  const SizedBox(height: 12),
                  Text(_reviewedCount > 0 ? 'All done for now — reviewed $_reviewedCount card(s).' : 'Nothing due right now.'),
                ],
              ),
            );
          }

          final card = _queue.first;
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text('${_queue.length} card(s) left', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _isRevealed = !_isRevealed),
                    child: Card(
                      elevation: 2,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                card['front'] as String,
                                style: Theme.of(context).textTheme.headlineSmall,
                                textAlign: TextAlign.center,
                              ),
                              if (_isRevealed) ...[
                                const Divider(height: 32),
                                Text(
                                  card['back'] as String,
                                  style: Theme.of(context).textTheme.titleMedium,
                                  textAlign: TextAlign.center,
                                ),
                              ] else ...[
                                const SizedBox(height: 16),
                                Text('Tap to reveal', style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_isRevealed)
                  Row(
                    children: [
                      _ratingButton('Again', 'again', Colors.red),
                      _ratingButton('Hard', 'hard', Colors.orange),
                      _ratingButton('Good', 'good', Colors.green),
                      _ratingButton('Easy', 'easy', Colors.blue),
                    ],
                  )
                else
                  FilledButton(
                    onPressed: () => setState(() => _isRevealed = true),
                    child: const Text('Show answer'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _ratingButton(String label, String rating, Color color) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: color),
          onPressed: _isSubmitting ? null : () => _rate(rating),
          child: Text(label),
        ),
      ),
    );
  }
}
