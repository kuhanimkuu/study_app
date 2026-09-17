import 'package:flutter/material.dart';

import '../../../../../core/api/api_client.dart';
import '../../../questions/presentation/widgets/question_answer_input.dart';

/// Sequential multi-question quiz (blueprint Section 18) — reuses
/// `QuestionAnswerInput` per question (same widget `QuestionPracticeScreen`
/// uses) rather than a new input implementation, and `ApiClient.
/// submitAttempt` per question (the same grading path single-question
/// practice already uses — no separate "quiz"/"exam" grading concept on
/// the backend, this is purely a client-side sequencing feature).
///
/// A fresh `QuestionAnswerInput` is created per question via
/// `ValueKey(question['id'])` rather than one reused instance, so each
/// question starts with genuinely empty answer state (matching/ordering's
/// own internal setup already assumes a fresh widget per question).
///
/// `examMode` (blueprint's "Exams" — formal, distinct from casual
/// practice) is a display mode, not a new backend entity: per-question
/// feedback is withheld until a final review screen at the end, instead
/// of shown immediately after each Submit. Every answer still grades
/// through the same submitAttempt call in real time; nothing is deferred
/// server-side. Deliberately NOT built as a separate timed/graded Exam
/// model — that's real new backend scope, named as still deferred.
class QuizRunnerScreen extends StatefulWidget {
  const QuizRunnerScreen({
    super.key,
    required this.apiClient,
    required this.questions,
    this.title = 'Quiz',
    this.examMode = false,
  });

  final ApiClient apiClient;
  final List<Map<String, dynamic>> questions;
  final String title;
  final bool examMode;

  @override
  State<QuizRunnerScreen> createState() => _QuizRunnerScreenState();
}

class _QuizRunnerScreenState extends State<QuizRunnerScreen> {
  final _answerKey = GlobalKey<QuestionAnswerInputState>();

  int _index = 0;
  int _correctCount = 0;
  bool _isSubmitting = false;
  String? _error;
  Map<String, dynamic>? _result; // current question's grading result, null until submitted
  late final List<Map<String, dynamic>?> _examResults =
      List<Map<String, dynamic>?>.filled(widget.questions.length, null);
  bool _showFinalReview = false;

  Map<String, dynamic> get _currentQuestion => widget.questions[_index];
  bool get _isLastQuestion => _index == widget.questions.length - 1;

  Future<void> _submit() async {
    final answer = _answerKey.currentState?.currentAnswer;
    if (answer == null) {
      setState(() => _error = 'Enter an answer first.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final result = await widget.apiClient.submitAttempt(
        questionId: _currentQuestion['id'] as int,
        answer: answer,
      );
      if (result['correct'] as bool) _correctCount++;
      if (widget.examMode) {
        _examResults[_index] = result;
        _advanceExam();
      } else {
        setState(() => _result = result);
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _advanceExam() {
    if (_isLastQuestion) {
      setState(() => _showFinalReview = true);
    } else {
      setState(() {
        _index++;
        _error = null;
      });
    }
  }

  void _next() {
    if (_isLastQuestion) {
      Navigator.of(context).pop({'correct': _correctCount, 'total': widget.questions.length});
      return;
    }
    setState(() {
      _index++;
      _result = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showFinalReview) return _buildFinalReview(context);

    final question = _currentQuestion;
    final prompt = question['prompt'] as String;

    return Scaffold(
      appBar: AppBar(title: Text('${widget.title} (${_index + 1}/${widget.questions.length})')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          LinearProgressIndicator(value: (_index) / widget.questions.length, minHeight: 4),
          const SizedBox(height: 16),
          Text(prompt, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          Offstage(
            offstage: _result != null,
            child: QuestionAnswerInput(key: ValueKey(question['id']), question: question),
          ),
          if (widget.examMode || _result == null) ...[
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 8),
            ],
            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(widget.examMode && _isLastQuestion ? 'Submit exam' : 'Submit'),
            ),
          ] else
            _buildResult(context),
        ],
      ),
    );
  }

  Widget _buildResult(BuildContext context) {
    final result = _result!;
    final correct = result['correct'] as bool;
    final feedback = result['feedback'] as String?;
    final color = correct ? Colors.green : Theme.of(context).colorScheme.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(correct ? Icons.check_circle : Icons.cancel, color: color),
            const SizedBox(width: 8),
            Text(correct ? 'Correct' : 'Incorrect', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ],
        ),
        if (feedback != null && feedback.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(feedback),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _next,
          child: Text(_isLastQuestion ? 'Finish' : 'Next question'),
        ),
      ],
    );
  }

  Widget _buildFinalReview(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exam results')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '$_correctCount/${widget.questions.length} correct',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          for (int i = 0; i < widget.questions.length; i++) _buildReviewRow(context, i),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop({'correct': _correctCount, 'total': widget.questions.length}),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewRow(BuildContext context, int i) {
    final result = _examResults[i]!;
    final correct = result['correct'] as bool;
    final feedback = result['feedback'] as String?;
    final color = correct ? Colors.green : Theme.of(context).colorScheme.error;
    return Card(
      child: ListTile(
        leading: Icon(correct ? Icons.check_circle : Icons.cancel, color: color),
        title: Text(widget.questions[i]['prompt'] as String),
        subtitle: feedback != null && feedback.isNotEmpty ? Text(feedback) : null,
        isThreeLine: feedback != null && feedback.isNotEmpty,
      ),
    );
  }
}
