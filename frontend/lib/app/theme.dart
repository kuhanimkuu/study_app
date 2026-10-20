import 'package:flutter/material.dart';

/// Study OS design system, v3 — "playful study app" (2026-10-19).
///
/// The user's verdict on v2 (a near-literal match of the
/// `kuhanimkuu/DesignStudyOSMobileApp` prototype): "dull and too plain",
/// "looks generic", "home isn't inviting", "hard to find things". The
/// requested direction is Duolingo's energy + Quizlet/Anki's card-first
/// study modes + Khan Academy/Coursera's subject-and-progress structure,
/// with something of its own on top. What changes from v2:
///
/// - **Colour with a job.** v2 was one blue on grey. v3 keeps Focus Blue as
///   the brand, but gives every subject its own vivid colour
///   ([subjectPalette]) and gives motivation its own colours — orange for
///   streaks, green for success/correct, violet for XP-style stats — so a
///   screen reads at a glance instead of as a list of grey rows.
/// - **A rounded, friendly typeface.** Nunito (bundled, OFL — see
///   `assets/fonts/Nunito-OFL.txt`) at heavy weights for headings, buttons,
///   stats and nav; Inter stays for body copy, where its readability wins.
/// - **Chunky, tactile controls.** The primary button ([GradientButton])
///   is a solid face sitting on a darker "ledge" that presses down —
///   Duolingo's signature affordance. Cards get bigger radii and thicker
///   borders.
///
/// Every existing token name is kept (screens built against v2 still
/// compile and pick the new look up through the theme); new ones are added.
class StudyOsColors {
  // Primary — Focus Blue, slightly brighter than v2 for more energy.
  static const primary = Color(0xFF2F6FED);
  static const primaryDark = Color(0xFF1C4FC4);

  /// The darker "ledge" under chunky primary-blue buttons and cards.
  static const primaryLedge = Color(0xFF1A44A8);

  static const primaryLightOnLight = Color(0xFFE8F0FF);
  static const primaryLightOnDark = Color(0xFF17244A);

  // Accent — Growth Amber (kept for v2 call sites: mastery highlights).
  static const amber = Color(0xFFF5A623);
  static const amberLightOnLight = Color(0xFFFFF6E5);
  static const amberLightOnDark = Color(0xFF2B1E08);
  static const amberFgOnLight = Color(0xFF7C4A00);
  static const amberFgOnDark = Color(0xFFFFD58A);

  // Motivation colours (v3)
  /// Streak flame.
  static const streak = Color(0xFFFF8A00);
  static const streakLedge = Color(0xFFD96F00);

  /// Correct answers, completed goals, "mastered".
  static const success = Color(0xFF22C55E);
  static const successLedge = Color(0xFF15A34A);

  /// XP-style stats (answers today, cards reviewed).
  static const xp = Color(0xFF8B5CF6);
  static const xpLedge = Color(0xFF6D3FD9);

  // Status
  static const greenOnLight = Color(0xFF16A34A);
  static const greenOnDark = Color(0xFF4ADE80);
  static const redOnLight = Color(0xFFE5484D);
  static const redOnDark = Color(0xFFFF7A7F);

  // Light theme surfaces/text/borders — a touch cooler and brighter than v2.
  static const bgLight = Color(0xFFF5F7FC);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const subtleLight = Color(0xFFEDF1FA);
  static const subtle2Light = Color(0xFFE2E8F6);
  static const fgLight = Color(0xFF111A33);
  static const fg2Light = Color(0xFF334155);
  static const fgMutedLight = Color(0xFF64748B);
  static const borderLight = Color(0xFFE0E6F2);

  // Dark theme surfaces/text/borders
  static const bgDark = Color(0xFF0B0F1C);
  static const surfaceDark = Color(0xFF141A2B);
  static const subtleDark = Color(0xFF1C2338);
  static const subtle2Dark = Color(0xFF252D47);
  static const fgDark = Color(0xFFF2F5FB);
  static const fg2Dark = Color(0xFFCBD5E1);
  static const fgMutedDark = Color(0xFF8D97AE);
  static const borderDark = Color(0xFF283152);

  /// Each subject (Knowledge Space) gets one of these, picked stably from
  /// its name (see `core/widgets/project_accent.dart`) — the
  /// Khan-Academy-style "every course has its colour" cue. Saturated
  /// enough to carry white text, distinct enough to tell apart at a glance.
  static const subjectPalette = [
    Color(0xFF2F6FED), // blue
    Color(0xFF8B5CF6), // violet
    Color(0xFF16A34A), // green
    Color(0xFFFF8A00), // orange
    Color(0xFFE2457A), // pink
    Color(0xFF0EA5A4), // teal
    Color(0xFFDC2F2F), // red
    Color(0xFF4F46E5), // indigo
  ];

  /// The brand gradient — the raised Chat button, the wordmark, the
  /// splash. Buttons themselves are now solid-with-a-ledge ([GradientButton]).
  static const brandGradient = LinearGradient(
    colors: [Color(0xFF4A86FF), Color(0xFF1C4FC4)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Home's daily-goal hero card.
  static const heroGradient = LinearGradient(
    colors: [Color(0xFF3B7BFF), Color(0xFF7A4DF5)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient heroPanel(Brightness brightness) {
    return brightness == Brightness.dark
        ? const LinearGradient(colors: [Color(0xFF17244A), Color(0xFF0B0F1C)], begin: Alignment.topLeft, end: Alignment.bottomRight)
        : const LinearGradient(colors: [Color(0xFFE8F0FF), Color(0xFFF5F7FC)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  }

  /// A darker shade of [color] for its chunky "ledge" (bottom edge).
  static Color ledgeOf(Color color) => Color.lerp(color, Colors.black, 0.22)!;
}

/// Bundled locally as app assets (`pubspec.yaml`'s `fonts:` section) —
/// deliberately NOT fetched at runtime via the `google_fonts` package,
/// whose first-use CDN download was a measured contributor to "the app
/// feels slow" (2026-09-19).
const _bodyFontFamily = 'Inter';
const displayFontFamily = 'Nunito';

/// Numbers and stats (percentages, counts, timers). v2 used JetBrains Mono
/// here; v3 uses heavy Nunito with tabular figures — still aligned digits,
/// but in the app's friendly voice instead of a code font. The name is kept
/// so every v2 call site picks up the new style.
TextStyle monoTextStyle(
  BuildContext context, {
  double? fontSize,
  FontWeight fontWeight = FontWeight.w800,
  Color? color,
}) {
  return TextStyle(
    fontFamily: displayFontFamily,
    fontSize: fontSize ?? 14,
    fontWeight: fontWeight,
    fontFeatures: const [FontFeature.tabularFigures()],
    color: color ?? Theme.of(context).colorScheme.onSurface,
  );
}

TextTheme _textTheme(Color primaryText, Color secondaryText, Color tertiaryText) {
  TextStyle display(double size, {FontWeight weight = FontWeight.w800, double spacing = -0.3}) => TextStyle(
        fontFamily: displayFontFamily,
        fontSize: size,
        fontWeight: weight,
        color: primaryText,
        letterSpacing: spacing,
        height: 1.15,
      );
  TextStyle body(double size, {FontWeight weight = FontWeight.w400, Color? color, double height = 1.5}) =>
      TextStyle(fontFamily: _bodyFontFamily, fontSize: size, fontWeight: weight, color: color ?? primaryText, height: height);

  return TextTheme(
    displayLarge: display(34),
    displayMedium: display(30),
    displaySmall: display(26),
    headlineLarge: display(24),
    headlineMedium: display(22),
    headlineSmall: display(20, spacing: -0.2),
    titleLarge: display(19, spacing: -0.1),
    titleMedium: display(16, weight: FontWeight.w800, spacing: 0),
    titleSmall: display(14, weight: FontWeight.w800, spacing: 0),
    bodyLarge: body(16),
    bodyMedium: body(14),
    bodySmall: body(12.5, color: secondaryText),
    labelLarge: const TextStyle(fontFamily: displayFontFamily, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.2)
        .copyWith(color: primaryText),
    labelMedium: TextStyle(fontFamily: displayFontFamily, fontSize: 13, fontWeight: FontWeight.w700, color: secondaryText),
    labelSmall: TextStyle(fontFamily: displayFontFamily, fontSize: 11.5, fontWeight: FontWeight.w700, color: tertiaryText, letterSpacing: 0.3),
  );
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
    onPrimaryContainer: isDark ? const Color(0xFF9DBBFF) : StudyOsColors.primaryDark,
    secondary: StudyOsColors.amber,
    onSecondary: isDark ? const Color(0xFF1A1205) : Colors.white,
    secondaryContainer: amberLight,
    onSecondaryContainer: amberFg,
    tertiary: StudyOsColors.xp,
    onTertiary: Colors.white,
    tertiaryContainer: isDark ? const Color(0xFF2A1F4D) : const Color(0xFFF1EBFF),
    onTertiaryContainer: isDark ? const Color(0xFFCDB8FF) : const Color(0xFF5B2FC4),
    error: red,
    onError: Colors.white,
    errorContainer: red.withValues(alpha: 0.12),
    onErrorContainer: red,
    surface: surface,
    onSurface: fg,
    onSurfaceVariant: fgMuted,
    surfaceContainerHighest: subtle,
    surfaceContainerHigh: subtle2,
    outline: border,
    outlineVariant: border,
    shadow: Colors.black,
  );

  const buttonText = TextStyle(fontFamily: displayFontFamily, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.2);
  final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  const buttonPadding = EdgeInsets.symmetric(horizontal: 22, vertical: 15);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: _bodyFontFamily,
    scaffoldBackgroundColor: bg,
    colorScheme: colorScheme,
    textTheme: _textTheme(fg, fg2, fgMuted),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: fg),
      titleTextStyle: TextStyle(fontFamily: displayFontFamily, color: fg, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.2),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: border, width: 1.5)),
      color: surface,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: TextStyle(fontFamily: displayFontFamily, fontSize: 15.5, fontWeight: FontWeight.w700, color: fg),
      subtitleTextStyle: TextStyle(fontFamily: _bodyFontFamily, fontSize: 12.5, color: fgMuted, height: 1.4),
      iconColor: fgMuted,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: subtle,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: border, width: 1.5)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: border, width: 1.5)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: StudyOsColors.primary, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: red, width: 1.5)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: red, width: 2)),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      hintStyle: TextStyle(color: fgMuted, fontSize: 14),
      labelStyle: TextStyle(color: fg2, fontSize: 13.5, fontWeight: FontWeight.w500),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: StudyOsColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: buttonText,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: StudyOsColors.primary,
        foregroundColor: Colors.white,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: fg,
        side: BorderSide(color: border, width: 2),
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: isDark ? const Color(0xFF7FA6FF) : StudyOsColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
        textStyle: const TextStyle(fontFamily: displayFontFamily, fontSize: 14, fontWeight: FontWeight.w800),
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
          fontFamily: displayFontFamily,
          fontSize: 11,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
          color: selected ? StudyOsColors.primary : fgMuted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(color: selected ? StudyOsColors.primary : fgMuted);
      }),
    ),
    tabBarTheme: TabBarThemeData(
      labelStyle: const TextStyle(fontFamily: displayFontFamily, fontSize: 14, fontWeight: FontWeight.w800),
      unselectedLabelStyle: const TextStyle(fontFamily: displayFontFamily, fontSize: 14, fontWeight: FontWeight.w700),
      labelColor: isDark ? const Color(0xFF7FA6FF) : StudyOsColors.primary,
      unselectedLabelColor: fgMuted,
      indicatorColor: StudyOsColors.primary,
      dividerColor: border,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: StudyOsColors.primary,
      foregroundColor: Colors.white,
      elevation: 3,
      highlightElevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      extendedTextStyle: buttonText,
    ),
    dividerTheme: DividerThemeData(color: border, thickness: 1.5, space: 1.5),
    chipTheme: ChipThemeData(
      backgroundColor: subtle,
      selectedColor: StudyOsColors.primary.withValues(alpha: isDark ? 0.28 : 0.12),
      labelStyle: TextStyle(fontFamily: displayFontFamily, fontSize: 13, fontWeight: FontWeight.w700, color: fg),
      side: BorderSide(color: border, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: StudyOsColors.primary,
      linearTrackColor: subtle2,
      circularTrackColor: subtle2,
      linearMinHeight: 8,
      borderRadius: BorderRadius.circular(99),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      contentTextStyle: const TextStyle(fontFamily: _bodyFontFamily, fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: TextStyle(fontFamily: displayFontFamily, fontSize: 20, fontWeight: FontWeight.w800, color: fg),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      showDragHandle: true,
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
