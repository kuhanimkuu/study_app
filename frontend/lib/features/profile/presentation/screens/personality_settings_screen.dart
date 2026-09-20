import 'package:flutter/material.dart';

import '../../../../core/api/api_client.dart';

/// The Moderator's 8-dimension personality (blueprint Section 7) — reaches
/// both /explain and ordinary chat server-side already; this is just the
/// first UI to edit it. Value sets matched exactly to
/// server/ai/personality/router.py's UpdatePersonality validation.
class PersonalitySettingsScreen extends StatefulWidget {
  const PersonalitySettingsScreen({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  State<PersonalitySettingsScreen> createState() => _PersonalitySettingsScreenState();
}

class _PersonalitySettingsScreenState extends State<PersonalitySettingsScreen> {
  static const _tones = ['friendly', 'neutral', 'formal', 'playful'];
  static const _formalities = ['casual', 'neutral', 'formal'];
  static const _verbosities = ['concise', 'moderate', 'detailed'];
  static const _teachingStyles = ['example_first', 'theory_first', 'socratic', 'story_driven'];

  String? _tone;
  String? _formality;
  String? _verbosity;
  String? _teachingStyle;
  double _humor = 0.5;
  double _encouragement = 0.5;
  double _directness = 0.5;
  double _challengeLevel = 0.5;

  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;
  String? _savedMessage;

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
      final p = await widget.apiClient.getPersonality();
      setState(() {
        _tone = p['tone'] as String;
        _formality = p['formality'] as String;
        _verbosity = p['verbosity'] as String;
        _teachingStyle = p['teaching_style'] as String;
        _humor = (p['humor'] as num).toDouble();
        _encouragement = (p['encouragement'] as num).toDouble();
        _directness = (p['directness'] as num).toDouble();
        _challengeLevel = (p['challenge_level'] as num).toDouble();
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _error = null;
      _savedMessage = null;
    });
    try {
      await widget.apiClient.updatePersonality(
        tone: _tone,
        formality: _formality,
        verbosity: _verbosity,
        teachingStyle: _teachingStyle,
        humor: _humor,
        encouragement: _encouragement,
        directness: _directness,
        challengeLevel: _challengeLevel,
      );
      setState(() => _savedMessage = 'Saved.');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _dropdown(String label, List<String> options, String? value, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [for (final o in options) DropdownMenuItem(value: o, child: Text(o))],
      onChanged: onChanged,
    );
  }

  Widget _slider(String label, double value, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label — ${value.toStringAsFixed(2)}'),
        Slider(value: value, onChanged: onChanged, divisions: 20, min: 0, max: 1),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Personality')),
      body: _isLoading && _tone == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _dropdown('Tone', _tones, _tone, (v) => setState(() => _tone = v)),
                const SizedBox(height: 12),
                _dropdown('Formality', _formalities, _formality, (v) => setState(() => _formality = v)),
                const SizedBox(height: 12),
                _dropdown('Verbosity', _verbosities, _verbosity, (v) => setState(() => _verbosity = v)),
                const SizedBox(height: 12),
                _dropdown('Teaching style', _teachingStyles, _teachingStyle, (v) => setState(() => _teachingStyle = v)),
                const SizedBox(height: 16),
                _slider('Humor', _humor, (v) => setState(() => _humor = v)),
                _slider('Encouragement', _encouragement, (v) => setState(() => _encouragement = v)),
                _slider('Directness', _directness, (v) => setState(() => _directness = v)),
                _slider('Challenge level', _challengeLevel, (v) => setState(() => _challengeLevel = v)),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                if (_savedMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(_savedMessage!, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                ],
                const SizedBox(height: 20),
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
