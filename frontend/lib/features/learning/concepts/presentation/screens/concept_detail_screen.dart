import 'package:flutter/material.dart';

import '../../../../../core/api/api_client.dart';
import '../../../../chat/presentation/widgets/block_view.dart';
import '../../../../practice/questions/presentation/screens/create_question_screen.dart';
import '../../../../practice/questions/presentation/screens/question_practice_screen.dart';

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
                  Text('Mastery', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: _mastery ?? 0, minHeight: 8),
                  const SizedBox(height: 4),
                  Text('${(((_mastery ?? 0)) * 100).round()}%'),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _isExplaining ? null : _explain,
                    icon: _isExplaining
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: const Text('Explain this to me'),
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
                  Text('Questions', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if ((_questions ?? []).isEmpty)
                    const Text('No questions yet. Tap + to add one.')
                  else
                    for (final q in _questions!)
                      Card(
                        child: ListTile(
                          title: Text((q as Map<String, dynamic>)['prompt'] as String),
                          subtitle: Text(q['type'] as String),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _practice(q),
                        ),
                      ),
                ],
              ),
      ),
    );
  }
}
