import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// A stable, deterministic accent color per project name — same small
/// palette the visual reference uses for its Study Spaces cards (each
/// project gets its own color instead of one flat default), reused by
/// `HomeScreen`'s Study Spaces shortcut and `ProjectsListScreen` so the
/// same project always shows the same color in both places.
const projectAccentPalette = [
  StudyOsColors.primary,
  Color(0xFF7C3AED),
  Color(0xFF059669),
  Color(0xFF0EA5E9),
  Color(0xFFDC2626),
];

Color projectAccentColor(String name) => projectAccentPalette[name.hashCode.abs() % projectAccentPalette.length];
