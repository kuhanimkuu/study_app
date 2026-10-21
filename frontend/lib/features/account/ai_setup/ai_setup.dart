import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/theme.dart';
import '../../../core/auth/auth_service.dart';
import 'ai_setup_screen.dart';

/// "Is AI set up?" for any screen (2026-10-21). Sage's answers, lessons,
/// generated flashcards and written-answer grading all need the student's
/// own AI key; most students don't know what that is, so without a loud
/// prompt the app just looked broken. main.dart attaches the one
/// AuthService; screens that only hold an ApiClient can still ask.
class AiSetup {
  AiSetup._();

  static AuthService? _auth;
  static final _unattached = ChangeNotifier();

  static void attach(AuthService auth) => _auth = auth;

  /// True when Sage can answer. Unattached (tests) counts as ready.
  static bool get ready => _auth?.modelSettings.aiReady ?? true;

  /// Notifies when the key is saved or removed.
  static Listenable get changes => _auth?.modelSettings ?? _unattached;

  /// Opens the setup when AI isn't ready; true once it is.
  static Future<bool> ensure(BuildContext context) async {
    if (ready || _auth == null) return true;
    await open(context);
    return ready;
  }

  /// Opens the setup even when a key is saved — for a key that stopped
  /// working (no credit left, deleted on the provider's side).
  static Future<void> open(BuildContext context) async {
    final auth = _auth;
    if (auth == null) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AiSetupScreen(authService: auth)));
  }

  /// Opens the setup by itself once per account (after the first-run tour),
  /// for a student who hasn't added a key.
  static Future<void> offerOnce(BuildContext context) async {
    final userId = _auth?.user?['id'];
    if (ready || userId == null) return;
    final key = 'ai_setup_offered_$userId';
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(key) ?? false) return;
      await prefs.setBool(key, true);
    } catch (_) {
      return;
    }
    if (context.mounted) await ensure(context);
  }
}

/// The loud "Sage can't answer yet" card, shown until a key is added — on
/// Home, both chats and the lesson screen. [compact] is the one-line
/// version that sits above a chat's text field.
class AiSetupBanner extends StatelessWidget {
  const AiSetupBanner({super.key, this.compact = false, this.margin = EdgeInsets.zero});

  final bool compact;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AiSetup.changes,
      builder: (context, _) {
        if (AiSetup.ready) return const SizedBox.shrink();
        final theme = Theme.of(context);
        const color = StudyOsColors.streak;
        final body = compact
            ? Row(
                children: [
                  const Icon(Icons.key_rounded, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: 'Sage can’t answer yet. ', style: TextStyle(fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface)),
                        TextSpan(text: 'Add your AI key first.', style: TextStyle(color: theme.colorScheme.onSurface)),
                      ]),
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: color, visualDensity: VisualDensity.compact),
                    onPressed: () => AiSetup.ensure(context),
                    child: const Text('Set up'),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.key_rounded, color: color, size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('Sage needs an AI key to work', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Answers, lessons, flashcards from your notes and marking written answers all use AI from a '
                    'provider you choose. Make a key on their website and paste it here — about 2 minutes. '
                    'Until then these features won’t work.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: color),
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text('Set up AI now'),
                    onPressed: () => AiSetup.ensure(context),
                  ),
                ],
              );
        return Container(
          margin: margin,
          padding: EdgeInsets.all(compact ? 10 : 16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            border: Border.all(color: color, width: 2),
            borderRadius: BorderRadius.circular(compact ? 14 : 20),
          ),
          child: body,
        );
      },
    );
  }
}
