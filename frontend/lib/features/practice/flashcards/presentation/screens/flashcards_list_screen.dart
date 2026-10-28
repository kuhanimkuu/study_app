import 'package:flutter/material.dart';

import '../../../../../app/theme.dart';
import '../../../../../core/api/api_client.dart';
import '../../../../../core/errors/error_presentation.dart';
import '../../../../../core/widgets/ai_generate_button.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../../../../core/widgets/tab_kit.dart';
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

  static bool _isDue(Map<String, dynamic> card, DateTime now) {
    final due = DateTime.tryParse(card['due'] as String? ?? '');
    return due == null || !due.isAfter(now);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cards = _flashcards ?? const <Map<String, dynamic>>[];
    final now = DateTime.now().toUtc();
    final due = cards.where((c) => _isDue(c, now)).length;
    final fresh = cards.where((c) => (c['reviews'] as num? ?? 0) == 0).length;
    // Soonest first: what's due now leads, then what comes up next.
    final sorted = [...cards]..sort((a, b) => (a['due'] as String? ?? '').compareTo(b['due'] as String? ?? ''));

    Widget body;
    if (_isLoading && _flashcards == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [Text(_error!, style: TextStyle(color: theme.colorScheme.error))],
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          const TabIntro(title: 'Flashcards', subtitle: 'Short reviews, spaced out so they stick.'),
          const SizedBox(height: 14),
          _reviewHero(context, total: cards.length, due: due),
          if (cards.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatChip(icon: Icons.style_rounded, value: '${cards.length}', label: cards.length == 1 ? 'card' : 'cards', color: StudyOsColors.xp),
                StatChip(icon: Icons.fiber_new_rounded, value: '$fresh', label: 'new', color: StudyOsColors.primary),
                StatChip(icon: Icons.schedule_rounded, value: '$due', label: 'due', color: StudyOsColors.streak),
              ],
            ),
          ],
          const SizedBox(height: 16),
          SageActionCard(
            color: StudyOsColors.xp,
            title: cards.isEmpty ? 'Want me to make your first deck?' : 'More cards?',
            body: cards.isEmpty
                ? 'I can turn this subject\'s sources into question-and-answer cards. Or tap + to write your own.'
                : 'I can make more cards from your sources. I skip ones you already have.',
            action: AiGenerateButton(
              label: 'Make cards from my sources',
              onGenerate: () async => generatedSummary(
                await widget.apiClient.generateFlashcards(widget.slug),
                'flashcards',
                'flashcard',
              ),
              onDone: _load,
            ),
          ),
          if (cards.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Your deck', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final card in sorted) ...[
              _cardTile(context, card, now),
              const SizedBox(height: 10),
            ],
          ],
        ],
      );
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createFlashcard,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New card'),
      ),
      body: RefreshIndicator(onRefresh: _load, child: body),
    );
  }

  /// The one thing this tab is for: how many cards are waiting, and the button to start.
  Widget _reviewHero(BuildContext context, {required int total, required int due}) {
    final theme = Theme.of(context);
    final caughtUp = total > 0 && due == 0;
    final String headline;
    final String line;
    if (total == 0) {
      headline = 'No cards yet';
      line = 'Make a deck below, then review a few minutes a day.';
    } else if (caughtUp) {
      headline = 'All caught up 🎉';
      line = 'Nothing is due right now. Come back when the next card is.';
    } else {
      headline = '$due ${due == 1 ? 'card' : 'cards'} to review';
      line = 'About ${(due * 0.25).ceil()} min. Keep your memory fresh.';
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8B5CF6), Color(0xFF4F46E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: StudyOsColors.xp.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(headline, style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(line, style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.85))),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // A little stack of cards.
              SizedBox(
                width: 54,
                height: 54,
                child: Stack(
                  children: [
                    for (final (i, angle) in [(0, -0.18), (1, 0.0), (2, 0.16)])
                      Positioned.fill(
                        child: Transform.rotate(
                          angle: angle,
                          child: Container(
                            margin: EdgeInsets.all(4.0 + i),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.35 + i * 0.25),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    const Center(child: Icon(Icons.style_rounded, color: StudyOsColors.xp, size: 22)),
                  ],
                ),
              ),
            ],
          ),
          if (total > 0 && !caughtUp) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: StudyOsColors.xpLedge,
                  minimumSize: const Size.fromHeight(46),
                  textStyle: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                onPressed: _review,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Start review'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cardTile(BuildContext context, Map<String, dynamic> card, DateTime now) {
    final theme = Theme.of(context);
    final isNew = (card['reviews'] as num? ?? 0) == 0;
    final dueNow = _isDue(card, now);
    final tag = isNew
        ? const TagPill(label: 'New', color: StudyOsColors.primary, icon: Icons.fiber_new_rounded)
        : TagPill(
            label: dueLabel(card['due'] as String?),
            color: dueNow ? StudyOsColors.streak : StudyOsColors.success,
            icon: dueNow ? Icons.schedule_rounded : Icons.check_circle_rounded,
          );
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Coloured spine, like the edge of an index card.
            Container(
              width: 6,
              decoration: BoxDecoration(
                color: isNew ? StudyOsColors.primary : (dueNow ? StudyOsColors.streak : StudyOsColors.success),
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(card['front'] as String, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.subdirectory_arrow_right_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            card['back'] as String,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    tag,
                  ],
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Delete card',
              onPressed: () => _deleteFlashcard(card['id'] as int),
            ),
          ],
        ),
      ),
    );
  }
}
