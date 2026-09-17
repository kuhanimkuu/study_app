import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Study OS design system — same disciplined "define every token once"
/// approach as Nexora's `theme.dart` (one color class + an explicit
/// TextTheme + explicit component themes, so no screen ever hand-rolls a
/// color/radius/font), but re-themed for a study tool rather than a social
/// feed: focus-blue primary, an amber "growth/mastery" accent (streaks,
/// XP, review completion) in place of Nexora's social purple, and a
/// slightly cooler, calmer surface/text scale.
class StudyOsColors {
  // Primary — Focus Blue
  static const primary = Color(0xFF2F6FED);
  static const primaryLight = Color(0xFF6C93F5);
  static const primaryDark = Color(0xFF1D4FBF);

  // Accent — Growth Amber (mastery/streaks/XP; the one deliberate "warm"
  // note against an otherwise cool, calm palette)
  static const accent = Color(0xFFF5A623);
  static const accentLight = Color(0xFFFFC65C);
  static const accentDark = Color(0xFFC97F00);

  // Light theme surfaces/text/borders
  static const backgroundLight = Color(0xFFFAFBFD);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceVariantLight = Color(0xFFEEF1F8);
  static const textPrimaryLight = Color(0xFF1A2233);
  static const textSecondaryLight = Color(0xFF5B6472);
  static const textTertiaryLight = Color(0xFF94A0B2);
  static const borderLight = Color(0xFFE3E7EE);
  static const dividerLight = Color(0xFFE3E7EE);

  // Dark theme surfaces/text/borders
  static const backgroundDark = Color(0xFF0D1117);
  static const surfaceDark = Color(0xFF161B22);
  static const surfaceVariantDark = Color(0xFF202631);
  static const textPrimaryDark = Color(0xFFF0F3F8);
  static const textSecondaryDark = Color(0xFFA6AEBB);
  static const textTertiaryDark = Color(0xFF6B7280);
  static const borderDark = Color(0xFF2A313D);
  static const dividerDark = Color(0xFF1E242D);

  // Status colors
  static const success = Color(0xFF16A34A);
  static const error = Color(0xFFE11D48);
  static const warning = Color(0xFFF59E0B);
  static const info = primary;

  /// The one gradient in the system — primary action buttons, the bottom
  /// nav's active-tab indicator, mastery/streak highlights, and the
  /// app's own wordmark (see `core/widgets/brand_wordmark.dart`).
  /// Everywhere else stays flat, theme-aware color (see Nexora ui.md
  /// §7.1: "brand gradient ... FAB, active chip, underline only" —
  /// restraint is what keeps a gradient feeling special instead of
  /// decorative).
  static const brandGradient = LinearGradient(
    colors: [primary, accent],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
}

TextTheme _withGoogleFonts(TextTheme base) {
  final heading = GoogleFonts.spaceGroteskTextTheme(base);
  final body = GoogleFonts.interTextTheme(base);
  return body.copyWith(
    displayLarge: heading.displayLarge,
    displayMedium: heading.displayMedium,
    displaySmall: heading.displaySmall,
    headlineLarge: heading.headlineLarge,
    headlineMedium: heading.headlineMedium,
    headlineSmall: heading.headlineSmall,
    titleLarge: heading.titleLarge,
    titleMedium: heading.titleMedium,
    titleSmall: heading.titleSmall,
  );
}

TextTheme _textTheme(Color primaryText, Color secondaryText, Color tertiaryText) {
  return TextTheme(
    displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: primaryText, letterSpacing: -0.5, height: 1.2),
    displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: primaryText, height: 1.2),
    displaySmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: primaryText, height: 1.2),
    headlineLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: primaryText),
    headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: primaryText),
    headlineSmall: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: primaryText),
    titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: primaryText),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: primaryText),
    titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: primaryText),
    bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: primaryText, height: 1.5, letterSpacing: 0.15),
    bodyMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: primaryText, height: 1.5, letterSpacing: 0.15),
    bodySmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: secondaryText, height: 1.5),
    labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: primaryText),
    labelMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: secondaryText),
    labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tertiaryText),
  );
}

final ThemeData studyOsLightTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  scaffoldBackgroundColor: StudyOsColors.backgroundLight,
  colorScheme: const ColorScheme.light(
    primary: StudyOsColors.primary,
    primaryContainer: StudyOsColors.primaryLight,
    secondary: StudyOsColors.accent,
    secondaryContainer: StudyOsColors.accentLight,
    tertiary: StudyOsColors.accent,
    surface: StudyOsColors.surfaceLight,
    surfaceContainerHighest: StudyOsColors.surfaceVariantLight,
    error: StudyOsColors.error,
    errorContainer: Color(0xFFFBD5DE),
    onErrorContainer: Color(0xFF7A0B26),
    onError: Colors.white,
    onPrimary: Colors.white,
    onSecondary: Colors.white,
    onSurface: StudyOsColors.textPrimaryLight,
    onSurfaceVariant: StudyOsColors.textSecondaryLight,
    outline: StudyOsColors.borderLight,
  ),
  textTheme: _withGoogleFonts(
    _textTheme(StudyOsColors.textPrimaryLight, StudyOsColors.textSecondaryLight, StudyOsColors.textTertiaryLight),
  ),
  appBarTheme: const AppBarTheme(
    elevation: 0,
    centerTitle: false,
    backgroundColor: StudyOsColors.backgroundLight,
    surfaceTintColor: Colors.transparent,
    iconTheme: IconThemeData(color: StudyOsColors.textPrimaryLight),
    titleTextStyle: TextStyle(color: StudyOsColors.textPrimaryLight, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.2),
  ),
  cardTheme: CardThemeData(
    elevation: 1,
    shadowColor: Colors.black.withValues(alpha: 0.05),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    color: StudyOsColors.surfaceLight,
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: StudyOsColors.surfaceVariantLight,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: StudyOsColors.primary, width: 2)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: StudyOsColors.error, width: 1)),
    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: StudyOsColors.error, width: 2)),
    contentPadding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
    hintStyle: const TextStyle(color: StudyOsColors.textTertiaryLight, fontSize: 15),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: StudyOsColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: StudyOsColors.primary,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: StudyOsColors.textPrimaryLight,
      side: const BorderSide(color: StudyOsColors.borderLight),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: StudyOsColors.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    ),
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: StudyOsColors.surfaceLight,
    elevation: 0,
    indicatorColor: StudyOsColors.primary.withValues(alpha: 0.12),
    labelTextStyle: WidgetStateProperty.resolveWith((states) {
      final selected = states.contains(WidgetState.selected);
      return TextStyle(
        fontSize: 11,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? StudyOsColors.primary : StudyOsColors.textSecondaryLight,
      );
    }),
    iconTheme: WidgetStateProperty.resolveWith((states) {
      final selected = states.contains(WidgetState.selected);
      return IconThemeData(color: selected ? StudyOsColors.primary : StudyOsColors.textSecondaryLight);
    }),
  ),
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    backgroundColor: StudyOsColors.primary,
    foregroundColor: Colors.white,
    elevation: 4,
    highlightElevation: 8,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
  dividerTheme: const DividerThemeData(color: StudyOsColors.dividerLight, thickness: 0.5, space: 0.5),
  chipTheme: ChipThemeData(
    backgroundColor: StudyOsColors.surfaceVariantLight,
    selectedColor: StudyOsColors.primary.withValues(alpha: 0.12),
    labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: StudyOsColors.textPrimaryLight),
    side: const BorderSide(color: StudyOsColors.borderLight),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
  ),
);

final ThemeData studyOsDarkTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: StudyOsColors.backgroundDark,
  colorScheme: const ColorScheme.dark(
    primary: StudyOsColors.primary,
    primaryContainer: StudyOsColors.primaryDark,
    secondary: StudyOsColors.accent,
    secondaryContainer: StudyOsColors.accentDark,
    tertiary: StudyOsColors.accentLight,
    surface: StudyOsColors.surfaceDark,
    surfaceContainerHighest: StudyOsColors.surfaceVariantDark,
    error: StudyOsColors.error,
    errorContainer: Color(0xFF4A0E1E),
    onErrorContainer: Color(0xFFFBD5DE),
    onError: Colors.white,
    onPrimary: Colors.white,
    onSecondary: Colors.white,
    onSurface: StudyOsColors.textPrimaryDark,
    onSurfaceVariant: StudyOsColors.textSecondaryDark,
    outline: StudyOsColors.borderDark,
    shadow: Color(0xFF000000),
  ),
  textTheme: _withGoogleFonts(
    _textTheme(StudyOsColors.textPrimaryDark, StudyOsColors.textSecondaryDark, StudyOsColors.textTertiaryDark),
  ),
  appBarTheme: const AppBarTheme(
    elevation: 0,
    centerTitle: false,
    backgroundColor: StudyOsColors.surfaceDark,
    surfaceTintColor: Colors.transparent,
    iconTheme: IconThemeData(color: StudyOsColors.textPrimaryDark),
    titleTextStyle: TextStyle(color: StudyOsColors.textPrimaryDark, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.2),
  ),
  cardTheme: CardThemeData(
    elevation: 2,
    shadowColor: Colors.black.withValues(alpha: 0.5),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: StudyOsColors.borderDark, width: 0.5)),
    color: StudyOsColors.surfaceDark,
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: StudyOsColors.surfaceVariantDark,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: StudyOsColors.primary, width: 2)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: StudyOsColors.error, width: 1)),
    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: StudyOsColors.error, width: 2)),
    contentPadding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
    hintStyle: const TextStyle(color: StudyOsColors.textTertiaryDark, fontSize: 15),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: StudyOsColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: StudyOsColors.primary,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: StudyOsColors.textPrimaryDark,
      side: const BorderSide(color: StudyOsColors.borderDark),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: StudyOsColors.primaryLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    ),
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: StudyOsColors.surfaceDark,
    elevation: 0,
    indicatorColor: StudyOsColors.primary.withValues(alpha: 0.2),
    labelTextStyle: WidgetStateProperty.resolveWith((states) {
      final selected = states.contains(WidgetState.selected);
      return TextStyle(
        fontSize: 11,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? StudyOsColors.primaryLight : StudyOsColors.textSecondaryDark,
      );
    }),
    iconTheme: WidgetStateProperty.resolveWith((states) {
      final selected = states.contains(WidgetState.selected);
      return IconThemeData(color: selected ? StudyOsColors.primaryLight : StudyOsColors.textSecondaryDark);
    }),
  ),
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    backgroundColor: StudyOsColors.primary,
    foregroundColor: Colors.white,
    elevation: 4,
    highlightElevation: 8,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
  dividerTheme: const DividerThemeData(color: StudyOsColors.dividerDark, thickness: 0.5, space: 0.5),
  chipTheme: ChipThemeData(
    backgroundColor: StudyOsColors.surfaceVariantDark,
    selectedColor: StudyOsColors.primary.withValues(alpha: 0.25),
    labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: StudyOsColors.textPrimaryDark),
    side: const BorderSide(color: StudyOsColors.borderDark),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
  ),
);
