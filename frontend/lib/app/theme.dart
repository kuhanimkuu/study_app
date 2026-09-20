import 'package:flutter/material.dart';

/// Study OS design system, v2 — re-tokenized to match the approved visual
/// reference (`kuhanimkuu/DesignStudyOSMobileApp`, a Figma-Make React
/// prototype covering Splash/Onboarding/Auth/Home/Learn/Chat/Planner/
/// Profile/Projects/Notes/Progress). Colors below are copied verbatim from
/// that prototype's `src/utils/colors.ts` (not re-derived/approximated),
/// so anything that looked "off-brand" against the reference before this
/// pass was a genuine token mismatch, not a rendering difference.
///
/// Typography: the reference uses plain Inter everywhere for prose/UI text
/// and JetBrains Mono specifically for numeric/data readouts (percentages,
/// timers, stat values, equation values) — see [monoTextStyle]. This
/// replaces v1's Space Grotesk-for-headings choice (the earlier Nexora-
/// inspired direction); Inter now carries headings too, matching the new
/// reference exactly rather than approximating it.
class StudyOsColors {
  // Primary — Focus Blue (identical value in both themes in the reference)
  static const primary = Color(0xFF2F6FED);
  static const primaryDark = Color(0xFF1D4FBF);

  // Per-theme "primary light" tint used for containers/badges/selected
  // states — NOT the same value in both themes (light uses a near-white
  // tint, dark uses a deep navy tint), per colors.ts.
  static const primaryLightOnLight = Color(0xFFEEF4FF);
  static const primaryLightOnDark = Color(0xFF162040);

  // Accent — Growth Amber (streaks, mastery, review completion)
  static const amber = Color(0xFFF5A623);
  static const amberLightOnLight = Color(0xFFFFF8EB);
  static const amberLightOnDark = Color(0xFF271B08);
  static const amberFgOnLight = Color(0xFF7C4A00);
  static const amberFgOnDark = Color(0xFF0C0E16);

  // Status
  static const greenOnLight = Color(0xFF059669);
  static const greenOnDark = Color(0xFF34D399);
  static const redOnLight = Color(0xFFDC2626);
  static const redOnDark = Color(0xFFF87171);

  // Light theme surfaces/text/borders
  static const bgLight = Color(0xFFFAFBFD);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const subtleLight = Color(0xFFEEF1F8);
  static const subtle2Light = Color(0xFFE4EAF8);
  static const fgLight = Color(0xFF0F172A);
  static const fg2Light = Color(0xFF334155);
  static const fgMutedLight = Color(0xFF64748B);
  static const borderLight = Color(0xFFE2E8F0);

  // Dark theme surfaces/text/borders
  static const bgDark = Color(0xFF0C0E16);
  static const surfaceDark = Color(0xFF141824);
  static const subtleDark = Color(0xFF1C2132);
  static const subtle2Dark = Color(0xFF232840);
  static const fgDark = Color(0xFFF1F5F9);
  static const fg2Dark = Color(0xFFCBD5E1);
  static const fgMutedDark = Color(0xFF8892A4);
  static const borderDark = Color(0xFF272D44);

  /// The one gradient in the system — primary action buttons, the raised
  /// center Chat tab, the app wordmark, streak/mastery highlights.
  /// Everywhere else stays flat, theme-aware color — restraint is what
  /// keeps a gradient feeling special instead of decorative.
  static const brandGradient = LinearGradient(
    colors: [Color(0xFF3D7EFF), Color(0xFF1D4FBF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// The hero-panel gradient behind Splash/Auth/Profile-header content —
  /// a soft near-white-to-primary-tint wash in light mode, a near-black
  /// navy-to-primary-tint wash in dark mode (both lifted from the
  /// reference's inline panel gradients).
  static LinearGradient heroPanel(Brightness brightness) {
    return brightness == Brightness.dark
        ? const LinearGradient(
            colors: [Color(0xFF162040), Color(0xFF0C0E16)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : const LinearGradient(
            colors: [Color(0xFFEEF4FF), Color(0xFFFAFBFD)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );
  }
}

/// Bundled locally as app assets (`pubspec.yaml`'s `fonts:` section, both
/// single-file variable fonts straight from Google's own font repo) —
/// deliberately NOT fetched at runtime via the `google_fonts` package.
/// That package's default behavior downloads font files from Google's CDN
/// the first time each is used, which was a real, measured contributor to
/// "the app feels slow" independent of which API backend it's pointed at
/// (found 2026-09-19 investigating a user report — see
/// STUDY_OS_PROGRESS.md's matching dated entry). Bundling trades ~1MB of
/// APK size for a startup that can never be network-bound on fonts.
const _interFontFamily = 'Inter';
const _monoFontFamily = 'JetBrains Mono';

/// JetBrains Mono, for numeric/data readouts only (percentages, timers,
/// stat tiles, equation values) — never for prose or UI labels. Matches
/// the reference's `font-mono` utility class usage exactly.
TextStyle monoTextStyle(
  BuildContext context, {
  double? fontSize,
  FontWeight fontWeight = FontWeight.w600,
  Color? color,
}) {
  return TextStyle(
    fontFamily: _monoFontFamily,
    fontSize: fontSize ?? 14,
    fontWeight: fontWeight,
    color: color ?? Theme.of(context).colorScheme.onSurface,
  );
}

TextTheme _textTheme(Color primaryText, Color secondaryText, Color tertiaryText) {
  return TextTheme(
    displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: primaryText, letterSpacing: -0.5, height: 1.2),
    displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: primaryText, letterSpacing: -0.4, height: 1.2),
    displaySmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: primaryText, letterSpacing: -0.3, height: 1.2),
    headlineLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: primaryText, letterSpacing: -0.3),
    headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: primaryText, letterSpacing: -0.2),
    headlineSmall: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: primaryText, letterSpacing: -0.1),
    titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: primaryText),
    titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: primaryText),
    titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryText),
    bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: primaryText, height: 1.5),
    bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: primaryText, height: 1.5),
    bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: secondaryText, height: 1.5),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primaryText),
    labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: secondaryText),
    labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: tertiaryText, letterSpacing: 0.4),
  ).apply(fontFamily: _interFontFamily);
}

ThemeData _buildTheme({
  required Brightness brightness,
  required Color bg,
  required Color surface,
  required Color subtle,
  required Color subtle2,
  required Color fg,
  required Color fg2,
  required Color fgMuted,
  required Color border,
  required Color primaryLight,
  required Color amberLight,
  required Color amberFg,
  required Color green,
  required Color red,
}) {
  final isDark = brightness == Brightness.dark;
  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: StudyOsColors.primary,
    onPrimary: Colors.white,
    primaryContainer: primaryLight,
    onPrimaryContainer: StudyOsColors.primary,
    secondary: StudyOsColors.amber,
    onSecondary: isDark ? StudyOsColors.amberFgOnDark : Colors.white,
    secondaryContainer: amberLight,
    onSecondaryContainer: amberFg,
    tertiary: StudyOsColors.amber,
    onTertiary: Colors.white,
    error: red,
    onError: Colors.white,
    errorContainer: red.withValues(alpha: 0.12),
    onErrorContainer: red,
    surface: surface,
    onSurface: fg,
    onSurfaceVariant: fgMuted,
    surfaceContainerHighest: subtle,
    outline: border,
    outlineVariant: border,
    shadow: Colors.black,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: bg,
    colorScheme: colorScheme,
    textTheme: _textTheme(fg, fg2, fgMuted),
    appBarTheme: AppBarTheme(
      elevation: 0,
      centerTitle: false,
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: fg),
      titleTextStyle: TextStyle(fontFamily: _interFontFamily, color: fg, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.2),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: border)),
      color: surface,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: subtle,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: StudyOsColors.primary, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: red)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: red, width: 1.5)),
      contentPadding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      hintStyle: TextStyle(color: fgMuted, fontSize: 14),
      labelStyle: TextStyle(color: fg2, fontSize: 13),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: StudyOsColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: StudyOsColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: fg,
        side: BorderSide(color: border, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: StudyOsColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      elevation: 0,
      height: 72,
      indicatorColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 10,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected ? StudyOsColors.primary : fgMuted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(color: selected ? StudyOsColors.primary : fgMuted);
      }),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: StudyOsColors.primary,
      foregroundColor: Colors.white,
      elevation: 4,
      highlightElevation: 8,
    ),
    dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
    chipTheme: ChipThemeData(
      backgroundColor: subtle,
      selectedColor: StudyOsColors.primary.withValues(alpha: isDark ? 0.22 : 0.1),
      labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
      side: BorderSide(color: border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    ),
  );
}

final ThemeData studyOsLightTheme = _buildTheme(
  brightness: Brightness.light,
  bg: StudyOsColors.bgLight,
  surface: StudyOsColors.surfaceLight,
  subtle: StudyOsColors.subtleLight,
  subtle2: StudyOsColors.subtle2Light,
  fg: StudyOsColors.fgLight,
  fg2: StudyOsColors.fg2Light,
  fgMuted: StudyOsColors.fgMutedLight,
  border: StudyOsColors.borderLight,
  primaryLight: StudyOsColors.primaryLightOnLight,
  amberLight: StudyOsColors.amberLightOnLight,
  amberFg: StudyOsColors.amberFgOnLight,
  green: StudyOsColors.greenOnLight,
  red: StudyOsColors.redOnLight,
);

final ThemeData studyOsDarkTheme = _buildTheme(
  brightness: Brightness.dark,
  bg: StudyOsColors.bgDark,
  surface: StudyOsColors.surfaceDark,
  subtle: StudyOsColors.subtleDark,
  subtle2: StudyOsColors.subtle2Dark,
  fg: StudyOsColors.fgDark,
  fg2: StudyOsColors.fg2Dark,
  fgMuted: StudyOsColors.fgMutedDark,
  border: StudyOsColors.borderDark,
  primaryLight: StudyOsColors.primaryLightOnDark,
  amberLight: StudyOsColors.amberLightOnDark,
  amberFg: StudyOsColors.amberFgOnDark,
  green: StudyOsColors.greenOnDark,
  red: StudyOsColors.redOnDark,
);
