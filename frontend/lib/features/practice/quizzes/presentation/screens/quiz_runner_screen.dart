import 'package:flutter/material.dart';

import '../../../../../core/api/api_client.dart';
import '../../../../../core/widgets/gradient_button.dart';
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
            GradientButton(
              label: widget.examMode && _isLastQuestion ? 'Submit exam' : 'Submit',
              isLoading: _isSubmitting,
              onPressed: _isSubmitting ? null : _submit,
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
        const SizedBox(height: 24),
        GradientButton(
          label: _isLastQuestion ? 'Finish' : 'Next question',
          icon: _isLastQuestion ? Icons.flag_rounded : Icons.arrow_forward_rounded,
          onPressed: _next,
        ),
      ],
    );
  }

  Widget _buildFinalReview(BuildContext context) {
    final theme = Theme.of(context);
    final total = widget.questions.length;
    final scorePercent = total == 0 ? 0 : (_correctCount / total * 100).round();
    final scoreColor = Color.lerp(theme.colorScheme.error, const Color(0xFF16A34A), scorePercent / 100)!;

    return Scaffold(
      appBar: AppBar(title: const Text('Exam results')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(color: scoreColor.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Center(
                    child: Text(
                      '$scorePercent%',
                      style: theme.textTheme.headlineMedium?.copyWith(color: scoreColor, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text('$_correctCount/$total correct', style: theme.textTheme.titleMedium),
              ],
            ),
          ),
          const SizedBox(height: 24),
          for (int i = 0; i < widget.questions.length; i++) _buildReviewRow(context, i),
          const SizedBox(height: 8),
          GradientButton(
            label: 'Done',
            onPressed: () => Navigator.of(context).pop({'correct': _correctCount, 'total': widget.questions.length}),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewRow(BuildContext context, int i) {
    final result = _examResults[i]!;
    final correct = result['correct'] as bool;
    final feedback = result['feedback'] as String?;
    final color = correct ? const Color(0xFF16A34A) : Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(correct ? Icons.check_rounded : Icons.close_rounded, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.questions[i]['prompt'] as String, style: Theme.of(context).textTheme.bodyMedium),
                    if (feedback != null && feedback.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        feedback,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
