import 'dart:async';

import 'package:flutter/material.dart';

/// Shared by Login/Signup: shows a "waking up the server" hint once a
/// request has been in flight for a few seconds — see `ApiClient`'s
/// `_authRequestTimeout` doc comment for why this exists (this app's
/// default hosted backend is a Render free-tier deploy that fully spins
/// down after ~15 minutes idle; a cold request can take a long time
/// before responding). Without this, a slow-but-working cold start looks
/// identical to a hung app.
mixin ColdStartHintMixin<T extends StatefulWidget> on State<T> {
  static const _delay = Duration(seconds: 4);

  Timer? _coldStartTimer;
  bool coldStartHintVisible = false;

  void startColdStartTimer() {
    _coldStartTimer?.cancel();
    coldStartHintVisible = false;
    _coldStartTimer = Timer(_delay, () {
      if (mounted) setState(() => coldStartHintVisible = true);
    });
  }

  void cancelColdStartTimer() {
    _coldStartTimer?.cancel();
    if (coldStartHintVisible) setState(() => coldStartHintVisible = false);
  }

  @override
  void dispose() {
    _coldStartTimer?.cancel();
    super.dispose();
  }

  Widget buildColdStartHint(BuildContext context) {
    if (!coldStartHintVisible) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Waking up the server — this can take up to a minute on our free hosting tier.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
