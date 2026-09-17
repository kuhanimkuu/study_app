import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/auth/auth_service.dart';
import '../../../../core/settings/model_settings_service.dart';
import '../../../../core/widgets/list_item_card.dart';
import '../../../profile/presentation/screens/memory_screen.dart';
import '../../../profile/presentation/screens/personality_settings_screen.dart';

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

  final _educationLevelController = TextEditingController();
  final _courseController = TextEditingController();
  final _institutionController = TextEditingController();
  final _preferredLanguageController = TextEditingController();
  final _dailyStudyTargetController = TextEditingController();

  bool _isSaving = false;
  bool _isSavingProfile = false;
  bool _isDeleting = false;
  String? _error;
  String? _savedMessage;
  String? _profileSavedMessage;

  @override
  void initState() {
    super.initState();
    final user = widget.authService.user;
    _displayNameController.text = user?['display_name'] as String? ?? '';
    _educationLevelController.text = user?['education_level'] as String? ?? '';
    _courseController.text = user?['course'] as String? ?? '';
    _institutionController.text = user?['institution'] as String? ?? '';
    _preferredLanguageController.text = user?['preferred_language'] as String? ?? '';
    _dailyStudyTargetController.text = (user?['daily_study_target_minutes'] as int?)?.toString() ?? '';
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

  Future<void> _saveStudentProfile() async {
    setState(() {
      _isSavingProfile = true;
      _profileSavedMessage = null;
    });
    try {
      final targetText = _dailyStudyTargetController.text.trim();
      await widget.authService.updateStudentProfile(
        educationLevel: _educationLevelController.text.trim().isEmpty ? null : _educationLevelController.text.trim(),
        course: _courseController.text.trim().isEmpty ? null : _courseController.text.trim(),
        institution: _institutionController.text.trim().isEmpty ? null : _institutionController.text.trim(),
        preferredLanguage:
            _preferredLanguageController.text.trim().isEmpty ? null : _preferredLanguageController.text.trim(),
        dailyStudyTargetMinutes: targetText.isEmpty ? null : int.tryParse(targetText),
      );
      setState(() => _profileSavedMessage = 'Profile saved.');
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isSavingProfile = false);
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final passwordController = TextEditingController();
    String? dialogError;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Delete account?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This permanently deletes your account and everything in it — Knowledge '
                'Spaces, materials, mastery, memories, and history. This cannot be undone.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Confirm your password'),
              ),
              if (dialogError != null) ...[
                const SizedBox(height: 8),
                Text(dialogError!, style: TextStyle(color: Theme.of(dialogContext).colorScheme.error)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
              onPressed: () async {
                if (passwordController.text.isEmpty) {
                  setDialogState(() => dialogError = 'Enter your password.');
                  return;
                }
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Delete permanently'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isDeleting = true;
      _error = null;
    });
    try {
      await widget.authService.deleteAccount(password: passwordController.text);
      // AuthGate reacts to authService's user becoming null (same path as
      // logout) — nothing further to navigate here.
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.statusCode == 401 ? 'Incorrect password.' : e.message;
          _isDeleting = false;
        });
      }
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
          Center(
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(gradient: StudyOsColors.brandGradient, shape: BoxShape.circle),
                  child: Center(
                    child: Text(
                      (user?['display_name'] as String?)?.isNotEmpty == true
                          ? (user!['display_name'] as String)[0].toUpperCase()
                          : (user?['email'] as String? ?? '?')[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(user?['email'] as String? ?? '', style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
              ],
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _displayNameController,
            decoration: const InputDecoration(labelText: 'Display name'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _isSaving ? null : _saveDisplayName,
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Update profile'),
            ),
          ),
          const Divider(height: 32),
          Text('Student profile', style: Theme.of(context).textTheme.titleMedium),
          Text(
            'Optional — never required to use Study OS.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _educationLevelController,
            decoration: const InputDecoration(labelText: 'Education level'),
          ),
          const SizedBox(height: 8),
          TextField(controller: _courseController, decoration: const InputDecoration(labelText: 'Course / program')),
          const SizedBox(height: 8),
          TextField(controller: _institutionController, decoration: const InputDecoration(labelText: 'Institution')),
          const SizedBox(height: 8),
          TextField(
            controller: _preferredLanguageController,
            decoration: const InputDecoration(labelText: 'Preferred language'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _dailyStudyTargetController,
            decoration: const InputDecoration(labelText: 'Daily study target (minutes)'),
            keyboardType: TextInputType.number,
          ),
          if (_profileSavedMessage != null) ...[
            const SizedBox(height: 8),
            Text(_profileSavedMessage!, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _isSavingProfile ? null : _saveStudentProfile,
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Save profile'),
            ),
          ),
          const Divider(height: 32),
          Text('Personalization', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ListItemCard(
            icon: Icons.tune_outlined,
            title: 'Personality',
            subtitle: 'Tone, verbosity, teaching style, and more',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => PersonalitySettingsScreen(apiClient: widget.authService.apiClient)),
            ),
          ),
          ListItemCard(
            icon: Icons.psychology_outlined,
            iconColor: Theme.of(context).colorScheme.secondary,
            title: 'Memory',
            subtitle: 'Facts and preferences you\'ve told it to remember',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => MemoryScreen(apiClient: widget.authService.apiClient)),
            ),
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
          FilledButton.icon(
            onPressed: _isSaving ? null : _saveModelSettings,
            icon: _isSaving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined, size: 18),
            label: const Text('Save'),
          ),
          if (_settings.hasApiKey) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _isSaving ? null : _clearApiKey,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Clear key & use local model'),
            ),
          ],
          const Divider(height: 32),
          Text('Danger zone', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
              side: BorderSide(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.4)),
            ),
            onPressed: _isDeleting ? null : _confirmDeleteAccount,
            icon: _isDeleting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.delete_forever_outlined, size: 18),
            label: const Text('Delete account'),
          ),
        ],
      ),
    );
  }
}
