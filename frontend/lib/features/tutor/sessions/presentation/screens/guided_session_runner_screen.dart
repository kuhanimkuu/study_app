import 'package:flutter/material.dart';

import '../../../../../app/theme.dart';
import '../../../../../core/api/api_client.dart';
import '../../../../../core/widgets/empty_state.dart';
import '../../../../../core/widgets/gradient_button.dart';
import '../../../../chat/presentation/widgets/block_view.dart';
import '../../../../practice/questions/presentation/widgets/question_answer_input.dart';

/// One concept to walk through in a guided session, flattened out of a
/// StudySession's plan phases (blueprint Section 21 lists 4-6 phases; this
/// flattens them into one ordered queue of concepts to actually teach,
/// since "phase" itself has nothing to explain/practice — only its
/// concepts do). Phases with zero concepts (e.g. an empty reflection
/// phase) contribute nothing to the queue.
class _QueueItem {
  _QueueItem({required this.phaseLabel, required this.conceptId, required this.conceptName});
  final String phaseLabel;
  final int conceptId;
  final String conceptName;
}

/// Turns a StudySession's plan from a static phase/concept list into an
/// actual guided walkthrough — the blueprint's own north-star vertical
/// slice ("teach me something"), built entirely from existing endpoints
/// (explainConcept, listQuestions, submitAttempt) rather than a new
/// Moderator capability: per concept, explain it, then practice up to 2
/// of its existing questions (capped so a guided session has a
/// predictable length rather than growing with however many questions a
/// concept happens to have), then move to the next concept. Ends by
/// marking the underlying StudySession complete.
class GuidedSessionRunnerScreen extends StatefulWidget {
  const GuidedSessionRunnerScreen({super.key, required this.apiClient, required this.session});

  final ApiClient apiClient;
  final Map<String, dynamic> session;

  @override
  State<GuidedSessionRunnerScreen> createState() => _GuidedSessionRunnerScreenState();
}

enum _Stage { loadingExplain, explained, loadingQuestions, practicing, betweenConcepts, done }

class _GuidedSessionRunnerScreenState extends State<GuidedSessionRunnerScreen> {
  static const _phaseLabels = {
    'retrieval_practice': 'Retrieval practice',
    'focus_weak_concepts': 'Focus on weak concepts',
    'practice': 'Practice',
    'reflection': 'Reflection',
  };
  static const _maxQuestionsPerConcept = 2;

  final _answerKey = GlobalKey<QuestionAnswerInputState>();

  late final List<_QueueItem> _queue = _buildQueue();
  int _conceptIndex = 0;
  _Stage _stage = _Stage.loadingExplain;
  String? _error;

  List<dynamic>? _explainBlocks;
  List<Map<String, dynamic>> _questions = [];
  int _questionIndex = 0;
  Map<String, dynamic>? _questionResult;

  int _correctCount = 0;
  int _attemptedCount = 0;
  bool _isCompletingSession = false;

  List<_QueueItem> _buildQueue() {
    final plan = widget.session['plan'] as Map<String, dynamic>;
    final phases = plan['phases'] as List<dynamic>;
    final queue = <_QueueItem>[];
    for (final raw in phases) {
      final phase = raw as Map<String, dynamic>;
      final label = _phaseLabels[phase['phase']] ?? phase['phase'] as String;
      final concepts = (phase['concepts'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      for (final concept in concepts) {
        queue.add(_QueueItem(phaseLabel: label, conceptId: concept['id'] as int, conceptName: concept['name'] as String));
      }
    }
    return queue;
  }

  _QueueItem get _current => _queue[_conceptIndex];

  @override
  void initState() {
    super.initState();
    if (_queue.isEmpty) {
      _stage = _Stage.done;
    } else {
      _explainCurrent();
    }
  }

  Future<void> _explainCurrent() async {
    setState(() {
      _stage = _Stage.loadingExplain;
      _error = null;
      _explainBlocks = null;
    });
    try {
      final result = await widget.apiClient.explainConcept(_current.conceptId);
      setState(() {
        _explainBlocks = result['blocks'] as List<dynamic>;
        _stage = _Stage.explained;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _stage = _Stage.explained; // still let the student continue past a failed explanation
      });
    }
  }

  Future<void> _loadQuestions() async {
    setState(() {
      _stage = _Stage.loadingQuestions;
      _error = null;
    });
    try {
      final result = await widget.apiClient.listQuestions(_current.conceptId);
      final all = (result['questions'] as List<dynamic>).cast<Map<String, dynamic>>();
      setState(() {
        _questions = all.take(_maxQuestionsPerConcept).toList();
        _questionIndex = 0;
        _questionResult = null;
        _stage = _questions.isEmpty ? _Stage.betweenConcepts : _Stage.practicing;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _stage = _Stage.betweenConcepts;
      });
    }
  }

  Future<void> _submitAnswer() async {
    final answer = _answerKey.currentState?.currentAnswer;
    if (answer == null) {
      setState(() => _error = 'Enter an answer first.');
      return;
    }
    setState(() => _error = null);
    try {
      final result = await widget.apiClient.submitAttempt(
        questionId: _questions[_questionIndex]['id'] as int,
        answer: answer,
      );
      setState(() {
        _questionResult = result;
        _attemptedCount++;
        if (result['correct'] as bool) _correctCount++;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  void _nextQuestionOrConcept() {
    if (_questionIndex < _questions.length - 1) {
      setState(() {
        _questionIndex++;
        _questionResult = null;
      });
    } else {
      setState(() => _stage = _Stage.betweenConcepts);
    }
  }

  void _nextConcept() {
    if (_conceptIndex < _queue.length - 1) {
      setState(() => _conceptIndex++);
      _explainCurrent();
    } else {
      setState(() => _stage = _Stage.done);
    }
  }

  Future<void> _finishSession() async {
    setState(() => _isCompletingSession = true);
    try {
      await widget.apiClient.completeStudySession(widget.session['id'] as int);
    } on ApiException {
      // non-critical for this screen's own summary — the session-list
      // screen the student returns to will still show the true status.
    } finally {
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Guided session')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_stage == _Stage.done) return _buildDone(context);

    if (_queue.isEmpty) {
      return const EmptyState(
        icon: Icons.school_outlined,
        message: 'This plan has no concepts to guide you through.',
      );
    }

    return ListView(
      children: [
        LinearProgressIndicator(value: _conceptIndex / _queue.length, minHeight: 4),
        const SizedBox(height: 8),
        Text(_current.phaseLabel, style: Theme.of(context).textTheme.labelMedium),
        Text(_current.conceptName, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        if (_error != null) ...[
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
        ],
        ..._buildStageContent(context),
      ],
    );
  }

  List<Widget> _buildStageContent(BuildContext context) {
    switch (_stage) {
      case _Stage.loadingExplain:
        return const [Center(child: CircularProgressIndicator())];
      case _Stage.explained:
        return [
          if (_explainBlocks != null)
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
          const SizedBox(height: 16),
          FilledButton(onPressed: _loadQuestions, child: const Text('Continue to practice')),
        ];
      case _Stage.loadingQuestions:
        return const [Center(child: CircularProgressIndicator())];
      case _Stage.practicing:
        final question = _questions[_questionIndex];
        return [
          Text('Practice ${_questionIndex + 1}/${_questions.length}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Text(question['prompt'] as String, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          Offstage(
            offstage: _questionResult != null,
            child: QuestionAnswerInput(key: ValueKey(question['id']), question: question),
          ),
          const SizedBox(height: 16),
          if (_questionResult == null)
            GradientButton(label: 'Submit', onPressed: _submitAnswer)
          else
            _buildQuestionResult(context),
        ];
      case _Stage.betweenConcepts:
        return [
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(gradient: StudyOsColors.brandGradient, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 32),
            ),
          ),
          const SizedBox(height: 12),
          Text('Done with "${_current.conceptName}".', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          GradientButton(
            label: _conceptIndex < _queue.length - 1 ? 'Next concept' : 'Finish session',
            icon: Icons.arrow_forward_rounded,
            onPressed: _nextConcept,
          ),
        ];
      case _Stage.done:
        return const [];
    }
  }

  Widget _buildQuestionResult(BuildContext context) {
    final correct = _questionResult!['correct'] as bool;
    final feedback = _questionResult!['feedback'] as String?;
    final color = correct ? const Color(0xFF16A34A) : Theme.of(context).colorScheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(correct ? Icons.check_circle_rounded : Icons.cancel_rounded, color: color),
                  const SizedBox(width: 8),
                  Text(correct ? 'Correct' : 'Incorrect', style: TextStyle(color: color, fontWeight: FontWeight.w800)),
                ],
              ),
              if (feedback != null && feedback.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(feedback),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        GradientButton(label: 'Continue', icon: Icons.arrow_forward_rounded, onPressed: _nextQuestionOrConcept),
      ],
    );
  }

  Widget _buildDone(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(gradient: StudyOsColors.brandGradient, shape: BoxShape.circle),
            child: const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 44),
          ),
          const SizedBox(height: 20),
          Text('Session walkthrough complete', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          if (_attemptedCount > 0)
            Text(
              '$_correctCount/$_attemptedCount practice questions correct',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          const SizedBox(height: 28),
          SizedBox(
            width: 240,
            child: GradientButton(
              label: 'Mark session complete',
              isLoading: _isCompletingSession,
              onPressed: _isCompletingSession ? null : _finishSession,
            ),
          ),
        ],
      ),
    );
  }
}
