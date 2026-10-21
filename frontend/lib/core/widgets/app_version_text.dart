import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// "Study OS 1.0.9 (build 10)" — at the bottom of Profile and the login
/// screen, so a student can say which version they have (2026-10-21).
/// Read from the installed app, so it can never go stale.
class AppVersionText extends StatelessWidget {
  const AppVersionText({super.key, this.info});

  /// Tests pass a fixed one; the app reads the installed package.
  final PackageInfo? info;

  static Future<String> label([PackageInfo? info]) async {
    final i = info ?? await PackageInfo.fromPlatform();
    return i.buildNumber.isEmpty ? i.version : '${i.version} (build ${i.buildNumber})';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<String>(
      future: label(info),
      builder: (context, snapshot) => Text(
        snapshot.hasData ? 'Study OS ${snapshot.data}' : 'Study OS',
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
