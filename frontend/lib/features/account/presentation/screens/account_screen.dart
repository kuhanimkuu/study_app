import 'package:flutter/material.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/auth/auth_service.dart';
import '../../../../core/settings/model_settings_service.dart';

/// Profile + BYOK model preference. "backend" chooses between the app's
/// free local model and the user's own Anthropic/OpenAI key.
///
/// Local-first pivot: the backend/model name/API key are NOT server state
/// (see ModelSettingsService) — they're stored on-device and only ever
/// sent, encrypted, on the one /api/ask/text call that needs them (see
/// ChatScreen). This screen edits ModelSettingsService directly; there is
/// no "save to server" step for BYOK anymore.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  ModelSettingsService get _settings => widget.authService.modelSettings;

  late String _backend = _settings.backend;
  late final _modelNameController = TextEditingController(text: _settings.modelName ?? '');
  final _apiKeyController = TextEditingController();
  final _displayNameController = TextEditingController();

  bool _isSaving = false;
  String? _error;
  String? _savedMessage;

  @override
  void initState() {
    super.initState();
    _displayNameController.text = widget.authService.user?['display_name'] as String? ?? '';
    if (_settings.hasApiKey) _apiKeyController.text = _settings.apiKey!;
  }

  Future<void> _saveModelSettings() async {
    setState(() {
      _isSaving = true;
      _error = null;
      _savedMessage = null;
    });
    try {
      await _settings.save(
        backend: _backend,
        modelName: _modelNameController.text.trim().isEmpty ? null : _modelNameController.text.trim(),
        apiKey: _apiKeyController.text.isEmpty ? null : _apiKeyController.text,
      );
      setState(() => _savedMessage = 'Saved on this device.');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _clearApiKey() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await _settings.save(backend: 'local');
      _apiKeyController.clear();
      setState(() {
        _backend = 'local';
        _savedMessage = 'Switched back to the local model.';
      });
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveDisplayName() async {
    setState(() {
      _isSaving = true;
      _error = null;
      _savedMessage = null;
    });
    try {
      await widget.authService.updateDisplayName(_displayNameController.text.trim());
      setState(() => _savedMessage = 'Profile updated.');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.authService.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () => widget.authService.logout(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(user?['email'] as String? ?? '', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          TextField(
            controller: _displayNameController,
            decoration: const InputDecoration(labelText: 'Display name'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: _isSaving ? null : _saveDisplayName, child: const Text('Update profile')),
          ),
          const Divider(height: 32),
          Text('AI backend', style: Theme.of(context).textTheme.titleMedium),
          Text(
            'Stored only on this device — never uploaded except, encrypted, '
            'when a request actually needs it.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: _backend,
            onChanged: (value) => setState(() => _backend = value ?? 'local'),
            child: const Column(
              children: [
                RadioListTile<String>(value: 'local', title: Text('Local model (free, on the server)')),
                RadioListTile<String>(value: 'anthropic', title: Text('Anthropic (Claude) — bring your own key')),
                RadioListTile<String>(value: 'openai', title: Text('OpenAI — bring your own key')),
              ],
            ),
          ),
          if (_backend != 'local') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _apiKeyController,
              decoration: InputDecoration(
                labelText: _settings.hasApiKey ? 'API key (already set)' : 'API key',
                hintText: _backend == 'anthropic' ? 'sk-ant-...' : 'sk-...',
              ),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _modelNameController,
              decoration: const InputDecoration(labelText: 'Model name (optional override)'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (_savedMessage != null) ...[
            const SizedBox(height: 12),
            Text(_savedMessage!, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _isSaving ? null : _saveModelSettings,
            child: _isSaving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
          if (_settings.hasApiKey) ...[
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _isSaving ? null : _clearApiKey, child: const Text('Clear key & use local model')),
          ],
        ],
      ),
    );
  }
}
