import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme.dart';
import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/sage_mascot.dart';

/// Step-by-step AI key setup (2026-10-21): choose a provider, open its key
/// page, paste the key, and "Test and save" — the server tries it with one
/// tiny call (server/routers/ai_check.py), so a wrong key or an account
/// with no credit is caught here, in plain words. Same providers, pages and
/// steps as the website's /ai/ guide; no prices, since providers change them.
class AiSetupScreen extends StatefulWidget {
  const AiSetupScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  State<AiSetupScreen> createState() => _AiSetupScreenState();
}

class _Provider {
  const _Provider(this.id, this.name, this.blurb, this.keyUrl, this.steps, {this.recommended = false});

  final String id;
  final String name;
  final String blurb;
  final String keyUrl;
  final List<String> steps;
  final bool recommended;
}

const _providers = [
  _Provider(
    'deepseek', 'DeepSeek', 'A good place to start: low prices, and it works well for studying.',
    'https://platform.deepseek.com/api_keys',
    ['Sign up at platform.deepseek.com', 'Add a little credit under Top up', 'Open API keys → Create new API key, and copy it'],
    recommended: true,
  ),
  _Provider(
    'openai', 'OpenAI (GPT)', 'The company behind ChatGPT. A ChatGPT subscription doesn’t include this — it’s billed separately.',
    'https://platform.openai.com/api-keys',
    ['Sign up at platform.openai.com', 'Add credit under Settings → Billing', 'Open API keys → Create new secret key, and copy it'],
  ),
  _Provider(
    'anthropic', 'Anthropic (Claude)', 'The makers of Claude. Billed separately from any Claude subscription.',
    'https://console.anthropic.com/settings/keys',
    ['Sign up at console.anthropic.com', 'Add credit under Billing', 'Open API keys → Create key, and copy it'],
  ),
];

const _guideUrl = 'https://studyos.helioho.st/ai/';

class _AiSetupScreenState extends State<AiSetupScreen> {
  _Provider _provider = _providers.first;
  final _keyController = TextEditingController();
  bool _obscure = true;
  bool _testing = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _open(String url) async {
    final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Open $url in your browser.')));
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) setState(() => _keyController.text = text);
  }

  Future<void> _testAndSave() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'Paste your key first.');
      return;
    }
    setState(() {
      _testing = true;
      _error = null;
    });
    try {
      await widget.authService.testAndSaveKey(backend: _provider.id, apiKey: key);
      setState(() => _done = true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set up AI')),
      body: SafeArea(child: _done ? _buildDone(context) : _buildSetup(context)),
    );
  }

  Widget _buildDone(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Center(child: SageMascot(size: 120, mood: SageMood.cheer)),
        const SizedBox(height: 16),
        Text('Sage is ready!', style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          'Your ${_provider.name} key works. It’s saved encrypted on this phone. You can change it any time in Profile → AI model.',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        GradientButton(label: 'Start learning', onPressed: () => Navigator.of(context).pop(true)),
      ],
    );
  }

  Widget _buildSetup(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const SageMascot(size: 72, mood: SageMood.happy),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Sage needs an AI key to work', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Study OS is free. Its AI runs on a provider you pick: make a key on their website, add a little credit '
          'there, and paste the key here once. You pay them directly for what you use. Your key stays encrypted on '
          'this phone.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        Text('1. Choose a provider', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final provider in _providers) _providerCard(context, provider),
        const SizedBox(height: 16),
        Text('2. Make your key', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final (i, step) in _provider.steps.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 24, child: Text('${String.fromCharCode(97 + i)}.', style: theme.textTheme.bodyMedium)),
                Expanded(child: Text(step, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          icon: const Icon(Icons.open_in_new_rounded),
          label: Text('Open ${_provider.name}’s key page'),
          onPressed: () => _open(_provider.keyUrl),
        ),
        const SizedBox(height: 20),
        Text('3. Paste it here', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        TextField(
          controller: _keyController,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: '${_provider.name} API key',
            hintText: _provider.id == 'anthropic' ? 'sk-ant-…' : 'sk-…',
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(tooltip: 'Paste', icon: const Icon(Icons.content_paste_rounded), onPressed: _paste),
                IconButton(
                  tooltip: _obscure ? 'Show' : 'Hide',
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ],
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 16),
        GradientButton(label: 'Test and save', icon: Icons.check_rounded, isLoading: _testing, onPressed: _testing ? null : _testAndSave),
        const SizedBox(height: 12),
        Center(
          child: TextButton(onPressed: () => _open(_guideUrl), child: const Text('Step-by-step guide on our website')),
        ),
      ],
    );
  }

  Widget _providerCard(BuildContext context, _Provider provider) {
    final theme = Theme.of(context);
    final selected = provider.id == _provider.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? StudyOsColors.primary : theme.colorScheme.outline, width: selected ? 2.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() {
          _provider = provider;
          _error = null;
        }),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: selected ? StudyOsColors.primary : theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(provider.name, style: theme.textTheme.titleSmall),
                        if (provider.recommended) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: StudyOsColors.success, borderRadius: BorderRadius.circular(999)),
                            child: const Text('Recommended', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(provider.blurb, style: theme.textTheme.bodySmall),
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
