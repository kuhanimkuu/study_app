import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// A small circular mastery readout (percentage inside a progress ring) —
/// matches the visual reference's Learn screen concept rows. Distinct from
/// `ConceptsListScreen`'s icon-badge+linear-bar treatment on purpose: two
/// real, deliberately different shapes for the same number, chosen per
/// screen the way the reference itself does (ring on Learn, bar on Home).
class MasteryRing extends StatelessWidget {
  const MasteryRing({super.key, required this.mastery, this.size = 44});

  /// 0.0-1.0.
  final double mastery;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = mastery >= 0.75 ? theme.colorScheme.primary : (mastery >= 0.5 ? StudyOsColors.amber : theme.colorScheme.error);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: mastery,
            strokeWidth: 4,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(color),
          ),
          Text('${(mastery * 100).round()}', style: monoTextStyle(context, fontSize: size * 0.24, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
