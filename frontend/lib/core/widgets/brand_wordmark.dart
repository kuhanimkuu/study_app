import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// The app's name, rendered in the brand gradient via `ShaderMask` — the
/// literal wordmark rather than plain themed text. A third, deliberate
/// exception to `StudyOsColors.brandGradient`'s "CTA + nav indicator
/// only" rule (see `app/theme.dart`): the app's own name is allowed to
/// carry the brand mark wherever it appears as a heading, same as
/// Nexora's splash screen treats its own wordmark.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.style, this.text = 'STUDY OS'});

  final TextStyle? style;
  final String text;

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? Theme.of(context).textTheme.titleLarge;
    return ShaderMask(
      shaderCallback: (bounds) => StudyOsColors.brandGradient.createShader(bounds),
      child: Text(text, style: baseStyle?.copyWith(color: Colors.white)),
    );
  }
}
