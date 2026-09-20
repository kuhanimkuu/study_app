import 'dart:math';

import 'package:flutter/material.dart';

/// The answer-input half of `question_practice_screen.dart`, extracted so
/// the new sequential Quiz runner can reuse the same 10 per-type input
/// widgets rather than duplicating them — first reuse outside the single-
/// question practice screen, same "prove it wasn't over-specialized to one
/// call site" reasoning as `server/ai/moderator/style.py`'s extraction.
///
/// Callers read the current answer via `GlobalKey<QuestionAnswerInputState>`
/// (`.currentState?.currentAnswer`) rather than a change callback — matches
/// how the original screen pulled the answer once, on submit, rather than
/// tracking it reactively on every keystroke.
class QuestionAnswerInput extends StatefulWidget {
  const QuestionAnswerInput({super.key, required this.question});

  final Map<String, dynamic> question;

  @override
  QuestionAnswerInputState createState() => QuestionAnswerInputState();
}

class QuestionAnswerInputState extends State<QuestionAnswerInput> {
  String? _selectedOption; // mcq / true_false
  final _answerController = TextEditingController(); // short_answer/essay/fill_in_blank/numerical/equation
  final Set<String> _selectedMultiOptions = {}; // multi_select
  final Map<String, String?> _matchSelections = {}; // matching: left item -> chosen right item
  List<String> _orderItems = []; // ordering: current (student-arranged) order

  String get _type => widget.question['type'] as String;
  List<String> get _options => ((widget.question['options'] as List<dynamic>?) ?? []).cast<String>();
  List<String> get _matchRightOptions => _options.where((o) => o.startsWith('R:')).map((o) => o.substring(2)).toList();

  @override
  void initState() {
    super.initState();
    _setUpForType();
  }

  void _setUpForType() {
    if (_type == 'matching') {
      for (final o in _options) {
        if (o.startsWith('L:')) _matchSelections[o.substring(2)] = null;
      }
    }
    if (_type == 'ordering') {
      _orderItems = List<String>.from(_options)..shuffle(Random());
    }
  }

  /// Null means "no answer entered yet" — callers should refuse to submit.
  dynamic get currentAnswer {
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

  /// Clears the entered answer without changing question — used by "Try
  /// another attempt at the same question" flows.
  void reset() {
    setState(() {
      _selectedOption = null;
      _answerController.clear();
      _selectedMultiOptions.clear();
      for (final key in _matchSelections.keys) {
        _matchSelections[key] = null;
      }
      if (_type == 'ordering') _orderItems = List<String>.from(_options)..shuffle(Random());
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

  @override
  Widget build(BuildContext context) {
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
}
