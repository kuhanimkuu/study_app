import 'package:flutter/material.dart';

/// The one row anatomy every list screen in this app should use instead
/// of a bare `ListTile`: a themed `Card` (radius 16 via `app/theme.dart`)
/// with a tinted, rounded icon badge on the left — the same "icon-led
/// row" idea as Nexora's avatar-led `PostCard` header, scaled down to
/// list-row size rather than a full social card. Adopted in Projects,
/// Flashcards, Notes, and Home's goal list; older/unrelated rows aren't
/// retrofitted just to use this.
class ListItemCard extends StatelessWidget {
  const ListItemCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
    this.subtitleMaxLines = 1,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Defaults to the theme's primary — pass a different color (e.g.
  /// `StudyOsColors.accent`) to distinguish one row type from another.
  final Color? iconColor;
  final int subtitleMaxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = iconColor ?? theme.colorScheme.primary;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        maxLines: subtitleMaxLines,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}
