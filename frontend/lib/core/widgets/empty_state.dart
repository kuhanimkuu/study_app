import 'package:flutter/material.dart';

/// A single informational message on its own screen/tab (no list, no
/// error) — "search this project's material", "no generated documents
/// yet", and the like. Same icon+text shape as `AsyncListView`'s empty
/// branch, pulled out standalone for the several screens that show one
/// message without a surrounding list. A bare `Center(child: Text(...))`
/// reads as unfinished; this is the one replacement for all of them.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message, this.iconColor});

  final IconData icon;
  final String message;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: iconColor ?? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
