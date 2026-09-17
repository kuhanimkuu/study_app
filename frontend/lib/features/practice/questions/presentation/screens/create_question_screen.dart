import 'package:flutter/material.dart';

import '../../../../../core/api/api_client.dart';

/// Authors one practice question on a concept. All 10 backend-gradable
/// types (see grading.py's docstring for exact answer shapes) now have a
/// form here.
///
/// Encoding notes for the two types whose "shape to show the student while
/// practicing" doesn't fit `correct_answer` directly (which is never sent
/// to a practicing student — see `Question.public()`):
///  - `matching`: `options` holds both sides as a flat, unpaired list,
///    prefixed `L:`/`R:` (e.g. `["L:Term A", "R:Def A"]`). Flat + unpaired
///    means position alone can't reveal which left matches which right —
///    only `correct_answer` (the hidden `{left: right}` map) does.
///  - `ordering`: `options` holds the same items as `correct_answer`, in
///    the correct order. That's safe only because the practice screen
///    always shuffles them before first display (never shows the
///    as-authored order) — see `question_practice_screen.dart`.
class CreateQuestionScreen extends StatefulWidget {
  const CreateQuestionScreen({super.key, required this.apiClient, required this.conceptId});

  final ApiClient apiClient;
  final int conceptId;

  @override
  State<CreateQuestionScreen> createState() => _CreateQuestionScreenState();
}

class _CreateQuestionScreenState extends State<CreateQuestionScreen> {
  static const _types = <String, String>{
    'mcq': 'Multiple choice',
    'true_false': 'True / False',
    'short_answer': 'Short answer',
    'essay': 'Essay',
    'fill_in_blank': 'Fill in the blank',
    'numerical': 'Numerical',
    'equation': 'Equation',
    'multi_select': 'Multi-select',
    'matching': 'Matching',
    'ordering': 'Ordering',
  };

  String _type = 'mcq';
  final _promptController = TextEditingController();
  final _answerController = TextEditingController(); // single-string-answer types
  final _toleranceController = TextEditingController(); // numerical only

  // Shared by mcq (radio, single correct answer via _answerController) and
  // multi_select (checkboxes, correct answers via _correctOptionIndices).
  final List<TextEditingController> _optionControllers = [TextEditingController(), TextEditingController()];
  final Set<int> _correctOptionIndices = {};

  // matching
  final List<TextEditingController> _matchLeftControllers = [TextEditingController(), TextEditingController()];
  final List<TextEditingController> _matchRightControllers = [TextEditingController(), TextEditingController()];

  // ordering
  final List<TextEditingController> _orderItemControllers = [TextEditingController(), TextEditingController()];

  bool _isSaving = false;
  String? _error;

  void _addOption() => setState(() => _optionControllers.add(TextEditingController()));

  void _removeOption(int index) => setState(() {
    _optionControllers.removeAt(index);
    // Re-derive from scratch rather than mutate-in-place: indices above the
    // removed one shift down by one, so this has to be computed before any
    // element of _correctOptionIndices is touched.
    final shifted = <int>{
      for (final i in _correctOptionIndices)
        if (i != index) (i > index ? i - 1 : i),
    };
    _correctOptionIndices
      ..clear()
      ..addAll(shifted);
  });

  void _addMatchPair() => setState(() {
    _matchLeftControllers.add(TextEditingController());
    _matchRightControllers.add(TextEditingController());
  });

  void _removeMatchPair(int index) => setState(() {
    _matchLeftControllers.removeAt(index);
    _matchRightControllers.removeAt(index);
  });

  void _addOrderItem() => setState(() => _orderItemControllers.add(TextEditingController()));

  void _removeOrderItem(int index) => setState(() => _orderItemControllers.removeAt(index));

  void _moveOrderItem(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _orderItemControllers.length) return;
    setState(() {
      final item = _orderItemControllers.removeAt(index);
      _orderItemControllers.insert(target, item);
    });
  }

  Future<void> _save() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      setState(() => _error = 'Prompt is required.');
      return;
    }

    dynamic correctAnswer;
    List<String>? options;
    double? tolerance;

    switch (_type) {
      case 'mcq':
        final answer = _answerController.text.trim();
        options = _optionControllers.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
        if (answer.isEmpty) {
          setState(() => _error = 'A correct answer is required.');
          return;
        }
        if (options.length < 2) {
          setState(() => _error = 'Add at least 2 options for a multiple-choice question.');
          return;
        }
        if (!options.contains(answer)) {
          setState(() => _error = 'The correct answer must match one of the options exactly.');
          return;
        }
        correctAnswer = answer;
      case 'true_false':
      case 'short_answer':
      case 'essay':
      case 'fill_in_blank':
      case 'equation':
        final answer = _answerController.text.trim();
        if (answer.isEmpty) {
          setState(() => _error = 'A correct answer is required.');
          return;
        }
        correctAnswer = answer;
      case 'numerical':
        final answer = _answerController.text.trim();
        if (answer.isEmpty || double.tryParse(answer) == null) {
          setState(() => _error = 'Correct answer must be a number.');
          return;
        }
        correctAnswer = answer;
        final toleranceText = _toleranceController.text.trim();
        if (toleranceText.isNotEmpty) {
          final parsedTolerance = double.tryParse(toleranceText);
          if (parsedTolerance == null) {
            setState(() => _error = 'Tolerance must be a number.');
            return;
          }
          tolerance = parsedTolerance;
        }
      case 'multi_select':
        final opts = _optionControllers.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
        if (opts.length < 2) {
          setState(() => _error = 'Add at least 2 options.');
          return;
        }
        final selected = _correctOptionIndices.where((i) => i < opts.length).map((i) => opts[i]).toList();
        if (selected.isEmpty) {
          setState(() => _error = 'Mark at least one option as correct.');
          return;
        }
        options = opts;
        correctAnswer = selected;
      case 'matching':
        final pairs = <MapEntry<String, String>>[];
        for (var i = 0; i < _matchLeftControllers.length; i++) {
          final left = _matchLeftControllers[i].text.trim();
          final right = _matchRightControllers[i].text.trim();
          if (left.isNotEmpty && right.isNotEmpty) pairs.add(MapEntry(left, right));
        }
        if (pairs.length < 2) {
          setState(() => _error = 'Add at least 2 complete matching pairs.');
          return;
        }
        correctAnswer = {for (final p in pairs) p.key: p.value};
        options = [for (final p in pairs) 'L:${p.key}', for (final p in pairs) 'R:${p.value}'];
      case 'ordering':
        final items = _orderItemControllers.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
        if (items.length < 2) {
          setState(() => _error = 'Add at least 2 items to order.');
          return;
        }
        correctAnswer = items;
        options = items;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await widget.apiClient.createQuestion(
        conceptId: widget.conceptId,
        type: _type,
        prompt: prompt,
        correctAnswer: correctAnswer,
        options: options,
        tolerance: tolerance,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildOptionList({required bool withCheckboxes}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Options', style: Theme.of(context).textTheme.labelLarge),
        for (int i = 0; i < _optionControllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                if (withCheckboxes)
                  Checkbox(
                    value: _correctOptionIndices.contains(i),
                    onChanged: (checked) => setState(() {
                      if (checked ?? false) {
                        _correctOptionIndices.add(i);
                      } else {
                        _correctOptionIndices.remove(i);
                      }
                    }),
                  ),
                Expanded(
                  child: TextField(
                    controller: _optionControllers[i],
                    decoration: InputDecoration(labelText: 'Option ${i + 1}'),
                  ),
                ),
                if (_optionControllers.length > 2)
                  IconButton(onPressed: () => _removeOption(i), icon: const Icon(Icons.remove_circle_outline)),
              ],
            ),
          ),
        TextButton.icon(onPressed: _addOption, icon: const Icon(Icons.add), label: const Text('Add option')),
        if (withCheckboxes) ...[
          const SizedBox(height: 4),
          Text(
            'Check every option that is a correct answer.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Widget _buildMatchingFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pairs to match', style: Theme.of(context).textTheme.labelLarge),
        for (int i = 0; i < _matchLeftControllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _matchLeftControllers[i],
                    decoration: const InputDecoration(labelText: 'Item'),
                  ),
                ),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward)),
                Expanded(
                  child: TextField(
                    controller: _matchRightControllers[i],
                    decoration: const InputDecoration(labelText: 'Matches to'),
                  ),
                ),
                if (_matchLeftControllers.length > 2)
                  IconButton(onPressed: () => _removeMatchPair(i), icon: const Icon(Icons.remove_circle_outline)),
              ],
            ),
          ),
        TextButton.icon(onPressed: _addMatchPair, icon: const Icon(Icons.add), label: const Text('Add pair')),
      ],
    );
  }

  Widget _buildOrderingFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Items, in the correct order', style: Theme.of(context).textTheme.labelLarge),
        for (int i = 0; i < _orderItemControllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Text('${i + 1}.', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _orderItemControllers[i],
                    decoration: const InputDecoration(labelText: 'Item'),
                  ),
                ),
                IconButton(
                  onPressed: i == 0 ? null : () => _moveOrderItem(i, -1),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  onPressed: i == _orderItemControllers.length - 1 ? null : () => _moveOrderItem(i, 1),
                  icon: const Icon(Icons.arrow_downward),
                ),
                if (_orderItemControllers.length > 2)
                  IconButton(onPressed: () => _removeOrderItem(i), icon: const Icon(Icons.remove_circle_outline)),
              ],
            ),
          ),
        TextButton.icon(onPressed: _addOrderItem, icon: const Icon(Icons.add), label: const Text('Add item')),
      ],
    );
  }

  Widget _buildTypeSpecificFields() {
    switch (_type) {
      case 'mcq':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOptionList(withCheckboxes: false),
            const SizedBox(height: 8),
            TextField(
              controller: _answerController,
              decoration: const InputDecoration(labelText: 'Correct answer (must match an option)'),
            ),
          ],
        );
      case 'multi_select':
        return _buildOptionList(withCheckboxes: true);
      case 'true_false':
        return DropdownButtonFormField<String>(
          initialValue: _answerController.text.isEmpty ? null : _answerController.text,
          decoration: const InputDecoration(labelText: 'Correct answer'),
          items: const [
            DropdownMenuItem(value: 'true', child: Text('True')),
            DropdownMenuItem(value: 'false', child: Text('False')),
          ],
          onChanged: (value) => setState(() => _answerController.text = value ?? ''),
        );
      case 'matching':
        return _buildMatchingFields();
      case 'ordering':
        return _buildOrderingFields();
      case 'numerical':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _answerController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'Correct answer (number)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _toleranceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Tolerance (optional, default is exact)'),
            ),
          ],
        );
      case 'equation':
        return TextField(
          controller: _answerController,
          decoration: const InputDecoration(labelText: 'Correct answer (e.g. x^2 + 2*x + 1)'),
        );
      case 'essay':
        return TextField(
          controller: _answerController,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Model answer / key points'),
        );
      default: // short_answer, fill_in_blank
        return TextField(
          controller: _answerController,
          decoration: const InputDecoration(labelText: 'Correct answer'),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add question')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) ...[
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 12),
          ],
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [for (final entry in _types.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value))],
            onChanged: (value) => setState(() => _type = value ?? 'mcq'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _promptController,
            decoration: const InputDecoration(labelText: 'Prompt'),
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          _buildTypeSpecificFields(),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined, size: 18),
            label: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
