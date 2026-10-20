import 'package:flutter/material.dart';

/// One of the colourful "try asking…" cards on an empty chat — the main
/// chat and each subject's chat (design v3).
class StarterCard extends StatelessWidget {
  const StarterCard({super.key, required this.label, required this.icon, required this.color, required this.onTap});

  final String label;
  final IconData icon;
  final Color color;

  /// Null disables the card (e.g. while Sage is already answering).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(18);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [BoxShadow(color: theme.colorScheme.outline, offset: const Offset(0, 3))],
      ),
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: theme.colorScheme.outline, width: 1.5)),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(11)),
                  child: Icon(icon, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lays starter cards out two to a row.
class StarterCardGrid extends StatelessWidget {
  const StarterCardGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [for (final c in children) SizedBox(width: width, child: c)],
        );
      },
    );
  }
}
