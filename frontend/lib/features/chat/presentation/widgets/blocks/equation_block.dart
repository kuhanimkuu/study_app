import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import 'text_block.dart' show plainMath;

/// Renders a `{"type": "equation", "latex": "x = 2", "source": "..."}`
/// block — produced by math_engine/symbolic via the moderator.
class EquationBlockView extends StatelessWidget {
  const EquationBlockView({super.key, required this.block});

  final Map<String, dynamic> block;

  @override
  Widget build(BuildContext context) {
    final latex = block['latex']?.toString() ?? '';
    final textStyle = TextStyle(fontSize: 18, color: DefaultTextStyle.of(context).style.color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Math.tex(
            latex,
            mathStyle: MathStyle.display,
            textStyle: textStyle,
            onErrorFallback: (error) => Text(plainMath(latex), style: textStyle),
          ),
        ),
      ),
    );
  }
}
