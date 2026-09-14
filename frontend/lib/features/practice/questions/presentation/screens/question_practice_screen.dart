import 'package:flutter/material.dart';

import '../../../../../core/api/api_client.dart';

/// Answer input matches the question's `type` — see grading.py's docstring
/// for the 3 shapes this slice supports (mcq/true_false/short_answer all
/// take a plain string, compared case/whitespace-insensitive server-side).
class QuestionPracticeScreen extends StatefulWidget {
  const QuestionPracticeScreen({super.key, required this.apiClient, required this.question});

  final ApiClient apiClient;
  final Map<String, dynamic> question;

  @override
  State<QuestionPracticeScreen> createState() => _QuestionPracticeScreenState();
}

class _QuestionPracticeScreenState extends State<QuestionPracticeScreen> {
  String? _selectedOption; // mcq / true_false
  final _answerController = TextEditingController(); // short_answer

  bool _isSubmitting = false;
  String? _error;
  Map<String, dynamic>? _result; // {correct, feedback, evaluated_by, mastery_after}

  String get _type => widget.question['type'] as String;

  Future<void> _submit() async {
    final answer = _type == 'short_answer' ? _answerController.text.trim() : _selectedOption;
    if (answer == null || answer.isEmpty) {
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
      _selectedOption = null;
      _answerController.clear();
      _error = null;
    });
  }

  Widget _buildAnswerInput() {
    if (_type == 'mcq') {
      final options = (widget.question['options'] as List<dynamic>?) ?? [];
      return RadioGroup<String>(
        groupValue: _selectedOption,
        onChanged: (value) => setState(() => _selectedOption = value),
        child: Column(
          children: [
            for (final option in options) RadioListTile<String>(title: Text(option as String), value: option),
          ],
        ),
      );
    }
    if (_type == 'true_false') {
      return RadioGroup<String>(
        groupValue: _selectedOption,
        onChanged: (value) => setState(() => _selectedOption = value),
        child: const Row(
          children: [
            Expanded(child: RadioListTile<String>(title: Text('True'), value: 'true')),
            Expanded(child: RadioListTile<String>(title: Text('False'), value: 'false')),
          ],
        ),
      );
    }
    return TextField(
      controller: _answerController,
      decoration: const InputDecoration(labelText: 'Your answer'),
      maxLines: 3,
    );
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
          if (_result == null) ...[
            _buildAnswerInput(),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 8),
            ],
            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Submit'),
            ),
          ] else ...[
            _buildResult(context),
          ],
        ],
      ),
    );
  }

  Widget _buildResult(BuildContext context) {
    final result = _result!;
    final correct = result['correct'] as bool;
    final feedback = result['feedback'] as String?;
    final masteryAfter = (result['mastery_after'] as Map<String, dynamic>)['mastery'] as num;
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
        const SizedBox(height: 16),
        Text('Mastery now: ${(masteryAfter * 100).round()}%'),
        LinearProgressIndicator(value: masteryAfter.toDouble(), minHeight: 6),
        const SizedBox(height: 24),
        Row(
          children: [
            OutlinedButton(onPressed: _retry, child: const Text('Try another')),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ],
    );
  }
}
