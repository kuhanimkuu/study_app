import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../../core/api/api_client.dart';

/// Answer input matches the question's `type` — see grading.py's docstring
/// for the exact shape each of the 10 gradable types expects.
///
/// `matching`/`ordering` decode the same `L:`/`R:`-prefixed and
/// same-order-as-correct-answer `options` conventions
/// `create_question_screen.dart` encodes — see that file's header comment.
/// Ordering's initial display order is shuffled here (never the
/// as-authored order) so the starting arrangement isn't already the
/// answer.
class QuestionPracticeScreen extends StatefulWidget {
  const QuestionPracticeScreen({super.key, required this.apiClient, required this.question});

  final ApiClient apiClient;
  final Map<String, dynamic> question;

  @override
  State<QuestionPracticeScreen> createState() => _QuestionPracticeScreenState();
}

class _QuestionPracticeScreenState extends State<QuestionPracticeScreen> {
  String? _selectedOption; // mcq / true_false
  final _answerController = TextEditingController(); // short_answer/essay/fill_in_blank/numerical/equation
  final Set<String> _selectedMultiOptions = {}; // multi_select
  final Map<String, String?> _matchSelections = {}; // matching: left item -> chosen right item
  List<String> _orderItems = []; // ordering: current (student-arranged) order

  bool _isSubmitting = false;
  String? _error;
  Map<String, dynamic>? _result; // {correct, feedback, evaluated_by, mastery_after}

  String get _type => widget.question['type'] as String;
  List<String> get _options => ((widget.question['options'] as List<dynamic>?) ?? []).cast<String>();

  @override
  void initState() {
    super.initState();
    if (_type == 'matching') {
      for (final o in _options) {
        if (o.startsWith('L:')) _matchSelections[o.substring(2)] = null;
      }
    }
    if (_type == 'ordering') {
      _orderItems = List<String>.from(_options)..shuffle(Random());
    }
  }

  List<String> get _matchRightOptions => _options.where((o) => o.startsWith('R:')).map((o) => o.substring(2)).toList();

  dynamic _currentAnswer() {
    switch (_type) {
      case 'mcq':
      case 'true_false':
        return _selectedOption;
      case 'multi_select':
        return _selectedMultiOptions.isEmpty ? null : _selectedMultiOptions.toList();
      case 'matching':
        if (_matchSelections.values.any((v) => v == null)) return null;
        return _matchSelections.map((k, v) => MapEntry(k, v!));
      case 'ordering':
        return _orderItems;
      default: // short_answer, essay, fill_in_blank, numerical, equation
        final text = _answerController.text.trim();
        return text.isEmpty ? null : text;
    }
  }

  Future<void> _submit() async {
    final answer = _currentAnswer();
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
      _selectedOption = null;
      _answerController.clear();
      _selectedMultiOptions.clear();
      for (final key in _matchSelections.keys) {
        _matchSelections[key] = null;
      }
      if (_type == 'ordering') _orderItems = List<String>.from(_options)..shuffle(Random());
      _error = null;
    });
  }

  void _moveOrderItem(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _orderItems.length) return;
    setState(() {
      final item = _orderItems.removeAt(index);
      _orderItems.insert(target, item);
    });
  }

  Widget _buildAnswerInput() {
    switch (_type) {
      case 'mcq':
        return RadioGroup<String>(
          groupValue: _selectedOption,
          onChanged: (value) => setState(() => _selectedOption = value),
          child: Column(
            children: [for (final option in _options) RadioListTile<String>(title: Text(option), value: option)],
          ),
        );
      case 'true_false':
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
      case 'multi_select':
        return Column(
          children: [
            for (final option in _options)
              CheckboxListTile(
                title: Text(option),
                value: _selectedMultiOptions.contains(option),
                onChanged: (checked) => setState(() {
                  if (checked ?? false) {
                    _selectedMultiOptions.add(option);
                  } else {
                    _selectedMultiOptions.remove(option);
                  }
                }),
              ),
          ],
        );
      case 'matching':
        final rightOptions = _matchRightOptions;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final left in _matchSelections.keys)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(child: Text(left)),
                    const Icon(Icons.arrow_forward),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _matchSelections[left],
                        hint: const Text('Choose match'),
                        items: [
                          for (final right in rightOptions) DropdownMenuItem(value: right, child: Text(right)),
                        ],
                        onChanged: (value) => setState(() => _matchSelections[left] = value),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      case 'ordering':
        return Column(
          children: [
            for (int i = 0; i < _orderItems.length; i++)
              Card(
                child: ListTile(
                  leading: Text('${i + 1}.'),
                  title: Text(_orderItems[i]),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: i == 0 ? null : () => _moveOrderItem(i, -1),
                        icon: const Icon(Icons.arrow_upward),
                      ),
                      IconButton(
                        onPressed: i == _orderItems.length - 1 ? null : () => _moveOrderItem(i, 1),
                        icon: const Icon(Icons.arrow_downward),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      case 'numerical':
        return TextField(
          controller: _answerController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: const InputDecoration(labelText: 'Your answer (number)'),
        );
      case 'equation':
        return TextField(
          controller: _answerController,
          decoration: const InputDecoration(labelText: 'Your answer (expression)'),
        );
      case 'essay':
        return TextField(
          controller: _answerController,
          decoration: const InputDecoration(labelText: 'Your answer'),
          maxLines: 8,
        );
      default: // short_answer, fill_in_blank
        return TextField(
          controller: _answerController,
          decoration: const InputDecoration(labelText: 'Your answer'),
          maxLines: 3,
        );
    }
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
