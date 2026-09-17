import 'package:flutter/material.dart';

import '../../../../../app/theme.dart';
import '../../../../../core/api/api_client.dart';
import '../../../../../core/widgets/empty_state.dart';
import '../../../../../core/widgets/gradient_button.dart';
import '../../../../chat/presentation/widgets/block_view.dart';
import '../../../../practice/questions/presentation/screens/create_question_screen.dart';
import '../../../../practice/questions/presentation/screens/question_practice_screen.dart';
import '../../../../practice/quizzes/presentation/screens/quiz_runner_screen.dart';

/// One concept: description, mastery, an on-demand explanation (reuses the
/// chat feature's BlockView rather than a new renderer — see the approved
/// plan), and its practice questions.
class ConceptDetailScreen extends StatefulWidget {
  const ConceptDetailScreen({super.key, required this.apiClient, required this.concept});

  final ApiClient apiClient;
  final Map<String, dynamic> concept;

  @override
  State<ConceptDetailScreen> createState() => _ConceptDetailScreenState();
}

class _ConceptDetailScreenState extends State<ConceptDetailScreen> {
  double? _mastery;
  List<dynamic>? _questions;
  bool _isLoading = false;
  String? _error;

  bool _isExplaining = false;
  String? _explainError;
  List<dynamic>? _explainBlocks;

  int get _conceptId => widget.concept['id'] as int;

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
      final mastery = await widget.apiClient.getConceptMastery(_conceptId);
      final questions = await widget.apiClient.listQuestions(_conceptId);
      setState(() {
        _mastery = (mastery['mastery'] as num).toDouble();
        _questions = questions['questions'] as List<dynamic>;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _explain() async {
    setState(() {
      _isExplaining = true;
      _explainError = null;
    });
    try {
      final result = await widget.apiClient.explainConcept(_conceptId);
      setState(() => _explainBlocks = result['blocks'] as List<dynamic>);
    } on ApiException catch (e) {
      setState(() => _explainError = e.message);
    } catch (e) {
      setState(() => _explainError = e.toString());
    } finally {
      if (mounted) setState(() => _isExplaining = false);
    }
  }

  Future<void> _addQuestion() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => CreateQuestionScreen(apiClient: widget.apiClient, conceptId: _conceptId),
      ),
    );
    if (created == true) _load();
  }

  Future<void> _practice(Map<String, dynamic> question) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => QuestionPracticeScreen(apiClient: widget.apiClient, question: question),
      ),
    );
    _load(); // mastery may have changed
  }

  Future<void> _startQuiz({required bool examMode}) async {
    final questions = (_questions ?? []).cast<Map<String, dynamic>>();
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (context) => QuizRunnerScreen(
          apiClient: widget.apiClient,
          questions: questions,
          title: widget.concept['name'] as String,
          examMode: examMode,
        ),
      ),
    );
    _load(); // mastery may have changed
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${examMode ? 'Exam' : 'Quiz'} complete: ${result['correct']}/${result['total']} correct')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.concept['name'] as String;
    final description = widget.concept['description'] as String?;

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      floatingActionButton: FloatingActionButton(onPressed: _addQuestion, child: const Icon(Icons.add)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading && _mastery == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  if (description != null && description.isNotEmpty) ...[
                    Text(description, style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 16),
                  ],
                  Builder(builder: (context) {
                    final theme = Theme.of(context);
                    final mastery = _mastery ?? 0;
                    final masteryColor = Color.lerp(theme.colorScheme.primary, StudyOsColors.accent, mastery)!;
                    return Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Mastery', style: theme.textTheme.titleMedium),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: mastery,
                                  minHeight: 8,
                                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                                  valueColor: AlwaysStoppedAnimation(masteryColor),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: masteryColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9999)),
                          child: Text(
                            '${(mastery * 100).round()}%',
                            style: theme.textTheme.titleSmall?.copyWith(color: masteryColor, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    );
                  }),
                  const SizedBox(height: 24),
                  GradientButton(
                    label: 'Explain this to me',
                    icon: Icons.auto_awesome_rounded,
                    isLoading: _isExplaining,
                    onPressed: _isExplaining ? null : _explain,
                  ),
                  if (_explainError != null) ...[
                    const SizedBox(height: 8),
                    Text(_explainError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  if (_explainBlocks != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final block in _explainBlocks!)
                              BlockView(block: block as Map<String, dynamic>, baseUrl: widget.apiClient.baseUrl),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Questions', style: Theme.of(context).textTheme.titleMedium),
                      if ((_questions ?? []).length >= 2)
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _startQuiz(examMode: false),
                              icon: const Icon(Icons.quiz_outlined),
                              label: const Text('Start quiz'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _startQuiz(examMode: true),
                              icon: const Icon(Icons.timer_outlined),
                              label: const Text('Exam mode'),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if ((_questions ?? []).isEmpty)
                    const EmptyState(icon: Icons.quiz_outlined, message: 'No questions yet. Tap + to add one.')
                  else
                    for (final q in _questions!)
                      Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _practice(q as Map<String, dynamic>),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.quiz_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(q['prompt'] as String, maxLines: 2, overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 2),
                                      Text(
                                        q['type'] as String,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                          ),
                        ),
                      ),
                ],
              ),
      ),
    );
  }
}
