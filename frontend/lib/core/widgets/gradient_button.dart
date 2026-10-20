import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// The primary action on a screen — log in, start a quiz, review cards.
///
/// v3 (2026-10-19): a chunky, tactile button — a solid face sitting on a
/// darker "ledge" (a hard, unblurred shadow) that the face presses down
/// onto while held, the Duolingo-style affordance that makes the one thing
/// to press obvious and satisfying. Name and API kept from v2 (where it
/// was a flat gradient) so every existing screen picks up the new look;
/// [color] is new and lets a screen use a motivation colour (green
/// "Start", orange "Review").
class GradientButton extends StatefulWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.color = StudyOsColors.primary,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final Color color;

  /// Full width (the default, for a screen's main action) or as wide as
  /// its label (inside cards).
  final bool expand;

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  static const _ledge = 4.0;
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inactive = widget.onPressed == null && !widget.isLoading;
    final enabled = widget.onPressed != null && !widget.isLoading;
    final face = inactive ? theme.colorScheme.surfaceContainerHigh : widget.color;
    final ledge = inactive ? theme.colorScheme.outline : StudyOsColors.ledgeOf(widget.color);
    final fg = inactive ? theme.colorScheme.onSurfaceVariant : Colors.white;
    final down = _pressed && enabled;

    final content = widget.isLoading
        ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation(Colors.white)))
        : Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[Icon(widget.icon, color: fg, size: 21), const SizedBox(width: 8)],
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: displayFontFamily, fontSize: 16.5, fontWeight: FontWeight.w900, letterSpacing: 0.3, color: fg),
                ),
              ),
            ],
          );

    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTapCancel: () => _setPressed(false),
        onTap: enabled ? widget.onPressed : null,
        child: Padding(
          // room for the ledge below the face
          padding: const EdgeInsets.only(bottom: _ledge),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 70),
            curve: Curves.easeOut,
            width: widget.expand ? double.infinity : null,
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            transform: Matrix4.translationValues(0, down ? _ledge : 0, 0),
            decoration: BoxDecoration(
              color: face,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: ledge, offset: Offset(0, down ? 0 : _ledge))],
            ),
            child: Center(widthFactor: 1, child: content),
          ),
        ),
      ),
    );
  }
}
