import 'package:flutter/material.dart';

import '../../../../../core/api/api_client.dart';

/// Authors one practice question on a concept. Only 3 of the 10
/// backend-supported types get a form here (mcq, true_false, short_answer)
/// — see the approved plan's "deliberately deferred" list for the rest.
class CreateQuestionScreen extends StatefulWidget {
  const CreateQuestionScreen({super.key, required this.apiClient, required this.conceptId});

  final ApiClient apiClient;
  final int conceptId;

  @override
  State<CreateQuestionScreen> createState() => _CreateQuestionScreenState();
}

class _CreateQuestionScreenState extends State<CreateQuestionScreen> {
  String _type = 'mcq';
  final _promptController = TextEditingController();
  final _answerController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];

  bool _isSaving = false;
  String? _error;

  void _addOption() => setState(() => _optionControllers.add(TextEditingController()));

  void _removeOption(int index) => setState(() => _optionControllers.removeAt(index));

  Future<void> _save() async {
    final prompt = _promptController.text.trim();
    final answer = _answerController.text.trim();
    if (prompt.isEmpty || answer.isEmpty) {
      setState(() => _error = 'Prompt and correct answer are required.');
      return;
    }
    List<String>? options;
    if (_type == 'mcq') {
      options = _optionControllers.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
      if (options.length < 2) {
        setState(() => _error = 'Add at least 2 options for a multiple-choice question.');
        return;
      }
      if (!options.contains(answer)) {
        setState(() => _error = 'The correct answer must match one of the options exactly.');
        return;
      }
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
        correctAnswer: answer,
        options: options,
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
            items: const [
              DropdownMenuItem(value: 'mcq', child: Text('Multiple choice')),
              DropdownMenuItem(value: 'true_false', child: Text('True / False')),
              DropdownMenuItem(value: 'short_answer', child: Text('Short answer')),
            ],
            onChanged: (value) => setState(() => _type = value ?? 'mcq'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _promptController,
            decoration: const InputDecoration(labelText: 'Prompt'),
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          if (_type == 'mcq') ...[
            Text('Options', style: Theme.of(context).textTheme.labelLarge),
            for (int i = 0; i < _optionControllers.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
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
            const SizedBox(height: 8),
            TextField(
              controller: _answerController,
              decoration: const InputDecoration(labelText: 'Correct answer (must match an option)'),
            ),
          ] else if (_type == 'true_false') ...[
            DropdownButtonFormField<String>(
              initialValue: _answerController.text.isEmpty ? null : _answerController.text,
              decoration: const InputDecoration(labelText: 'Correct answer'),
              items: const [
                DropdownMenuItem(value: 'true', child: Text('True')),
                DropdownMenuItem(value: 'false', child: Text('False')),
              ],
              onChanged: (value) => setState(() => _answerController.text = value ?? ''),
            ),
          ] else ...[
            TextField(
              controller: _answerController,
              decoration: const InputDecoration(labelText: 'Correct answer'),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}
