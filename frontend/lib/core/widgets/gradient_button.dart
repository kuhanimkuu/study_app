import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// The one gradient control in the design system (see `app/theme.dart`'s
/// `StudyOsColors.brandGradient` doc) — reserved for the single primary
/// action on a screen: log in / sign up, start a quiz, start a guided
/// session. Everything else stays flat theme color, so this stays a
/// signal ("this is the one thing to press here") instead of decoration.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || isLoading;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: Container(
        decoration: BoxDecoration(
          gradient: StudyOsColors.brandGradient,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ElevatedButton(
          onPressed: disabled ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ).copyWith(
            // The gradient container is the real surface — only dim it
            // for the disabled/loading state instead of letting the
            // button theme paint a flat grey over it.
            overlayColor: WidgetStateProperty.all(Colors.white.withValues(alpha: 0.08)),
          ),
          child: Opacity(
            opacity: isLoading ? 0.7 : 1,
            child: isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[Icon(icon, color: Colors.white, size: 20), const SizedBox(width: 8)],
                      Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
