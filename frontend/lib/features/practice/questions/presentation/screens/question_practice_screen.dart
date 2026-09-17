import 'package:flutter/material.dart';

import '../../../../../core/api/api_client.dart';
import '../../../../../core/widgets/gradient_button.dart';
import '../widgets/question_answer_input.dart';

/// Single-question practice — answer input is `QuestionAnswerInput` (see
/// that widget for the per-type UI/answer-shape details for all 10
/// gradable types); this screen owns submission, grading feedback, and
/// the "try another attempt" reset.
class QuestionPracticeScreen extends StatefulWidget {
  const QuestionPracticeScreen({super.key, required this.apiClient, required this.question});

  final ApiClient apiClient;
  final Map<String, dynamic> question;

  @override
  State<QuestionPracticeScreen> createState() => _QuestionPracticeScreenState();
}

class _QuestionPracticeScreenState extends State<QuestionPracticeScreen> {
  final _answerKey = GlobalKey<QuestionAnswerInputState>();

  bool _isSubmitting = false;
  String? _error;
  Map<String, dynamic>? _result; // {correct, feedback, evaluated_by, mastery_after}

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
        questionId: widget.question['id'] as int,
        answer: answer,
      );
      setState(() => _result = result);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _retry() {
    setState(() {
      _result = null;
      _error = null;
    });
    _answerKey.currentState?.reset();
  }

  @override
  Widget build(BuildContext context) {
    final prompt = widget.question['prompt'] as String;

    return Scaffold(
      appBar: AppBar(title: const Text('Practice')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(prompt, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          Offstage(
            offstage: _result != null,
            child: QuestionAnswerInput(key: _answerKey, question: widget.question),
          ),
          if (_result == null) ...[
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 8),
            ],
            GradientButton(label: 'Submit', isLoading: _isSubmitting, onPressed: _isSubmitting ? null : _submit),
          ] else ...[
            _buildResult(context),
          ],
        ],
      ),
    );
  }

  Widget _buildResult(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result!;
    final correct = result['correct'] as bool;
    final feedback = result['feedback'] as String?;
    final masteryAfter = (result['mastery_after'] as Map<String, dynamic>)['mastery'] as num;
    final color = correct ? const Color(0xFF16A34A) : theme.colorScheme.error;

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
        Text('Mastery now: ${(masteryAfter * 100).round()}%', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: masteryAfter.toDouble(),
            minHeight: 6,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try another'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GradientButton(label: 'Done', onPressed: () => Navigator.of(context).pop()),
            ),
          ],
        ),
      ],
    );
  }
}
