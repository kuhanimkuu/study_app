import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/analytics/streak.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/auth/auth_service.dart';
import '../../../../core/settings/model_settings_service.dart';
import '../../../history/presentation/screens/history_screen.dart';
import '../../../profile/presentation/screens/memory_screen.dart';
import '../../../profile/presentation/screens/personality_settings_screen.dart';
import '../../../progress/presentation/screens/progress_screen.dart';

/// Profile + BYOK model preference. Rebuilt to match the approved visual
/// reference's `Profile.tsx`: a gradient header card (avatar/name/email/
/// tags), a real quick-stats row, a "View progress" entry, selectable
/// AI-model cards, personalization entries, student-profile fields, a
/// Data & Privacy section, and a sign-out button.
///
/// Local-first pivot unchanged: the backend/model name/API key are NOT
/// server state (see ModelSettingsService) — stored on-device, only ever
/// sent encrypted on the one /api/ask/text call that needs them.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.authService, this.onOpenProjects});

  final AuthService authService;

  /// Projects is no longer a bottom-nav tab (see `app_shell.dart`) — this
  /// gives Profile its own entry point into it too, alongside Home's
  /// "Study spaces" shortcut, since a user deep in Learn/Planner/Chat
  /// would otherwise have to go back to Home first. Not present in the
  /// visual reference's own Profile screen — a deliberate judgment call
  /// for reachability, named here rather than silently deviating.
  final VoidCallback? onOpenProjects;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  ModelSettingsService get _settings => widget.authService.modelSettings;
  ApiClient get _apiClient => widget.authService.apiClient;

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
  bool _apiKeyVisible = false;
  String? _error;
  String? _savedMessage;
  String? _profileSavedMessage;

  int _streak = 0;
  double? _avgMastery;
  int _sessionsThisWeek = 0;

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
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final results = await Future.wait([_apiClient.getMastery(), _apiClient.getAttempts(), _apiClient.listStudySessions()]);
      final mastery = (results[0]['mastery'] as List<dynamic>).cast<Map<String, dynamic>>();
      final attempts = (results[1]['attempts'] as List<dynamic>).cast<Map<String, dynamic>>();
      final sessions = (results[2]['study_sessions'] as List<dynamic>).cast<Map<String, dynamic>>();

      final activity = [
        ...sessions.map((s) => {...s, '_timestamp': s['created_at']}),
        ...attempts.map((a) => {...a, '_timestamp': a['created_at']}),
      ];

      final weekCutoff = DateTime.now().subtract(const Duration(days: 7));
      final completedThisWeek = sessions.where((s) {
        if (s['status'] != 'completed') return false;
        return DateTime.parse(s['created_at'] as String).toLocal().isAfter(weekCutoff);
      }).length;

      final avg = mastery.isEmpty ? null : mastery.map((m) => (m['mastery'] as num).toDouble()).reduce((a, b) => a + b) / mastery.length;

      if (!mounted) return;
      setState(() {
        _streak = computeStudyStreak(activity);
        _avgMastery = avg;
        _sessionsThisWeek = completedThisWeek;
      });
    } catch (_) {
      // Stats are a nice-to-have on this screen — a failed fetch here
      // shouldn't block the rest of Account from rendering.
    }
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

  Widget _sectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title.toUpperCase(), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, letterSpacing: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = widget.authService.user;
    final displayName = (user?['display_name'] as String?)?.trim();
    final email = user?['email'] as String? ?? '';
    final course = user?['course'] as String?;
    final institution = user?['institution'] as String?;

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            decoration: BoxDecoration(gradient: StudyOsColors.heroPanel(theme.brightness)),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: const BoxDecoration(gradient: StudyOsColors.brandGradient, shape: BoxShape.circle),
                      child: Center(
                        child: Text(
                          (displayName?.isNotEmpty ?? false) ? displayName![0].toUpperCase() : (email.isNotEmpty ? email[0].toUpperCase() : '?'),
                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(displayName?.isNotEmpty == true ? displayName! : 'Student', style: theme.textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(email, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (course != null || institution != null) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              children: [
                                if (course != null)
                                  _Tag(label: course, filled: true),
                                if (institution != null)
                                  _Tag(label: institution, filled: false),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.logout_rounded), tooltip: 'Log out', onPressed: () => widget.authService.logout()),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _StatTile(value: '$_streak 🔥', label: 'Day streak')),
                    Expanded(child: _StatTile(value: '$_sessionsThisWeek', label: 'Sessions/wk')),
                    Expanded(child: _StatTile(value: _avgMastery == null ? '—' : '${(_avgMastery! * 100).round()}%', label: 'Avg mastery')),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProfileRow(
                  icon: Icons.insights_rounded,
                  label: 'View progress & analytics',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => ProgressScreen(apiClient: _apiClient))),
                ),
                if (widget.onOpenProjects != null)
                  _ProfileRow(icon: Icons.folder_outlined, label: 'Study spaces', onTap: widget.onOpenProjects),
                const SizedBox(height: 24),

                _sectionHeader(context, 'AI model'),
                Column(
                  children: [
                    for (final option in const [
                      (id: 'local', name: 'Local model', sub: 'Free, on the server — no key needed'),
                      (id: 'anthropic', name: 'Anthropic Claude', sub: 'Bring your own key'),
                      (id: 'openai', name: 'OpenAI GPT', sub: 'Bring your own key'),
                      (id: 'deepseek', name: 'DeepSeek', sub: 'Bring your own key'),
                    ])
                      _ModelOptionCard(
                        name: option.name,
                        subtitle: option.sub,
                        selected: _backend == option.id,
                        onTap: () => setState(() => _backend = option.id),
                      ),
                  ],
                ),
                if (_backend != 'local') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: !_apiKeyVisible,
                    decoration: InputDecoration(
                      labelText: _settings.hasApiKey ? 'API key (already set)' : 'API key',
                      hintText: _backend == 'anthropic' ? 'sk-ant-...' : 'sk-...',
                      prefixIcon: const Icon(Icons.vpn_key_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(_apiKeyVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _apiKeyVisible = !_apiKeyVisible),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _modelNameController,
                    decoration: const InputDecoration(labelText: 'Model name (optional override)'),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ],
                if (_savedMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(_savedMessage!, style: TextStyle(color: theme.colorScheme.primary)),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isSaving ? null : _saveModelSettings,
                        icon: _isSaving
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save_outlined, size: 18),
                        label: const Text('Save'),
                      ),
                    ),
                    if (_settings.hasApiKey) ...[
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _isSaving ? null : _clearApiKey,
                        icon: const Icon(Icons.restart_alt, size: 18),
                        label: const Text('Use local'),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 28),
                _sectionHeader(context, 'Personalization'),
                _ProfileRow(
                  icon: Icons.tune_outlined,
                  label: 'Personality',
                  sublabel: 'Tone, verbosity, teaching style, and more',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => PersonalitySettingsScreen(apiClient: _apiClient)),
                  ),
                ),
                _ProfileRow(
                  icon: Icons.psychology_outlined,
                  label: 'Memory',
                  sublabel: 'Facts and preferences you\'ve told it to remember',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => MemoryScreen(apiClient: _apiClient)),
                  ),
                ),

                const SizedBox(height: 28),
                _sectionHeader(context, 'Student profile'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        TextField(controller: _displayNameController, decoration: const InputDecoration(labelText: 'Display name')),
                        const SizedBox(height: 10),
                        TextField(controller: _educationLevelController, decoration: const InputDecoration(labelText: 'Education level')),
                        const SizedBox(height: 10),
                        TextField(controller: _courseController, decoration: const InputDecoration(labelText: 'Course / program')),
                        const SizedBox(height: 10),
                        TextField(controller: _institutionController, decoration: const InputDecoration(labelText: 'Institution')),
                        const SizedBox(height: 10),
                        TextField(controller: _preferredLanguageController, decoration: const InputDecoration(labelText: 'Preferred language')),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _dailyStudyTargetController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Daily study target (minutes)'),
                        ),
                        if (_profileSavedMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(_profileSavedMessage!, style: TextStyle(color: theme.colorScheme.primary)),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(onPressed: _isSaving ? null : _saveDisplayName, child: const Text('Save name')),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton(onPressed: _isSavingProfile ? null : _saveStudentProfile, child: const Text('Save profile')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 28),
                _sectionHeader(context, 'Data & privacy'),
                _ProfileRow(
                  icon: Icons.history_rounded,
                  label: 'Activity history',
                  sublabel: 'Ask questions about your own study history',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => HistoryScreen(apiClient: _apiClient))),
                ),
                _ProfileRow(
                  icon: Icons.delete_forever_outlined,
                  label: 'Delete account',
                  sublabel: 'Cannot be undone',
                  danger: true,
                  trailing: _isDeleting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : null,
                  onTap: _isDeleting ? null : _confirmDeleteAccount,
                ),

                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () => widget.authService.logout(),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Sign out'),
                    style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.filled});

  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: filled ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: filled ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        children: [
          Text(value, style: monoTextStyle(context, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.icon, required this.label, this.sublabel, this.onTap, this.trailing, this.danger = false});

  final IconData icon;
  final String label;
  final String? sublabel;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = danger ? theme.colorScheme.error : theme.colorScheme.onSurface;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: danger ? theme.colorScheme.error : theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w500)),
                    if (sublabel != null) Text(sublabel!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              trailing ?? Icon(Icons.chevron_right_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelOptionCard extends StatelessWidget {
  const _ModelOptionCard({required this.name, required this.subtitle, required this.selected, required this.onTap});

  final String name;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: selected ? theme.colorScheme.primaryContainer : theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? theme.colorScheme.primary : theme.colorScheme.outline, width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurface)),
                    Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
