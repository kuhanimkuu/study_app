import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// Renders a `{"type": "equation", "latex": "x = 2", "source": "..."}`
/// block — produced by math_engine/symbolic via the moderator.
class EquationBlockView extends StatelessWidget {
  const EquationBlockView({super.key, required this.block});

  final Map<String, dynamic> block;

  @override
  Widget build(BuildContext context) {
    final latex = block['latex']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Math.tex(
          latex,
          mathStyle: MathStyle.display,
          onErrorFallback: (error) => Text(latex, style: const TextStyle(fontFamily: 'monospace')),
        ),
      ),
    );
  }
}
