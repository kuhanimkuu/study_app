import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../app/theme.dart';
import '../../../../../core/widgets/gradient_button.dart';

/// Renders a `{"type": "model_unavailable", "message", "attempted_backend",
/// "suggested_backend", "suggested_model"}` block (json.md §6) — the free
/// local AI model call itself failed, not ambiguous input (that's still
/// a plain `clarification` block). Unlike a bare error message, this is
/// actionable: explains BYOK in three steps, names a suggested
/// backend/model, and gives a real way forward — a button into the
/// Account screen's AI-backend section (only shown when the host screen
/// can provide one; ChatScreen has an AuthService to build it from, other
/// BlockView call sites that don't just omit the callback) plus quick
/// links to where each provider's API keys are actually purchased, for
/// someone who doesn't have one yet.
class ModelUnavailableBlockView extends StatelessWidget {
  const ModelUnavailableBlockView({super.key, required this.block, this.onSetUpByok});

  final Map<String, dynamic> block;

  /// Navigates to wherever the host screen's BYOK settings live (Account
  /// screen). Null (button hidden) when the host screen can't build one —
  /// see BlockView's own doc comment.
  final VoidCallback? onSetUpByok;

  static const _providerKeyUrls = {
    'OpenAI': 'https://platform.openai.com/api-keys',
    'Anthropic': 'https://console.anthropic.com/settings/keys',
    'DeepSeek': 'https://platform.deepseek.com/api_keys',
  };

  Future<void> _openProviderKeyPage(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = block['message']?.toString() ?? 'The free local AI model is currently unavailable.';
    final suggestedBackend = block['suggested_backend']?.toString();
    final suggestedModel = block['suggested_model']?.toString();
    // Present when the *free* local model failed (BYOK is a fresh
    // suggestion then); absent when a BYOK backend's own call failed —
    // recommending itself as the fix would be nonsensical, so the copy
    // switches to "fix your existing setup" instead of "set one up".
    final isByokAlreadyConfigured = suggestedBackend == null;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: StudyOsColors.warning.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(Icons.cloud_off_rounded, size: 18, color: StudyOsColors.warning),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(message, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            isByokAlreadyConfigured ? 'Fix your API key setup:' : 'Bring your own key instead:',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          if (isByokAlreadyConfigured) ...[
            const _Step(number: 1, text: 'Double-check the API key you entered — a typo or expired key is the usual cause.'),
            const _Step(number: 2, text: 'Confirm the model name matches that provider (or leave it blank for the default).'),
            const _Step(number: 3, text: 'Open Account → AI backend to fix it, or switch backends entirely.'),
          ] else ...[
            const _Step(number: 1, text: 'Pick a provider (Anthropic, OpenAI, or DeepSeek) and get an API key.'),
            const _Step(number: 2, text: 'Open Account → AI backend, select that provider, and paste your key in.'),
            const _Step(number: 3, text: 'Optionally set a model name — leave blank for a sensible default.'),
          ],
          if (suggestedBackend != null && suggestedModel != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9999),
              ),
              child: Text(
                'Suggested: $suggestedBackend — $suggestedModel',
                style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary),
              ),
            ),
          ],
          if (onSetUpByok != null) ...[
            const SizedBox(height: 14),
            GradientButton(label: 'Set up my own API key', icon: Icons.key_rounded, onPressed: onSetUpByok),
          ],
          const SizedBox(height: 12),
          Text('Don\'t have a key yet?', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in _providerKeyUrls.entries)
                OutlinedButton.icon(
                  onPressed: () => _openProviderKeyPage(entry.value),
                  icon: const Icon(Icons.open_in_new, size: 14),
                  label: Text(entry.key),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Center(
              child: Text(
                '$number',
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
