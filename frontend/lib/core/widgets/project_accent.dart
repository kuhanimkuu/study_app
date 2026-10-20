import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// A stable accent colour per subject (Knowledge Space / project) — every
/// subject keeps its own colour everywhere it appears (Home tiles, the
/// Subjects list, its workspace header), the way each course has its own
/// colour on Khan Academy. Palette: `StudyOsColors.subjectPalette` (v3).
///
/// Hashed from the code units rather than `String.hashCode`, which Dart
/// doesn't promise to keep stable across releases — a subject must not
/// change colour after an app update.
const projectAccentPalette = StudyOsColors.subjectPalette;

int _stableHash(String s) {
  var h = 0;
  for (final unit in s.codeUnits) {
    h = (h * 31 + unit) & 0x7fffffff;
  }
  return h;
}

Color projectAccentColor(String name) => projectAccentPalette[_stableHash(name.trim().toLowerCase()) % projectAccentPalette.length];

/// An icon that fits the subject's name ("Cell Biology" → a leaf,
/// "Calculus" → a calculator); a book when nothing matches. Stems match
/// the START of a word, so "art" doesn't fire on "particle" or "start".
/// First match wins.
IconData subjectIcon(String name) {
  final words = name.toLowerCase().split(RegExp(r'[^a-z]+')).where((w) => w.isNotEmpty).toList();
  for (final (stems, icon) in _subjectIcons) {
    if (stems.any((stem) => words.any((w) => w.startsWith(stem)))) return icon;
  }
  return Icons.menu_book_rounded;
}

const _subjectIcons = <(List<String>, IconData)>[
  (['bio', 'microbio', 'cell', 'anatomy', 'genetic', 'ecology', 'botany', 'zoology'], Icons.eco_rounded),
  (['chem'], Icons.science_rounded),
  (['physic', 'mechanic', 'electric', 'thermo'], Icons.bolt_rounded),
  (['math', 'calculus', 'algebra', 'geometry', 'statistic', 'probability', 'trig'], Icons.calculate_rounded),
  (['comput', 'program', 'code', 'coding', 'software', 'python', 'java', 'data'], Icons.code_rounded),
  (['histor'], Icons.history_edu_rounded),
  (['geograph', 'earth', 'climate'], Icons.public_rounded),
  (['econ', 'business', 'finance', 'account', 'market'], Icons.trending_up_rounded),
  (['english', 'literat', 'language', 'french', 'spanish', 'swahili', 'kiswahili', 'german', 'grammar', 'writing'], Icons.translate_rounded),
  (['art', 'design', 'drawing'], Icons.palette_rounded),
  (['music'], Icons.music_note_rounded),
  (['psych', 'mind'], Icons.psychology_rounded),
  (['law', 'legal'], Icons.gavel_rounded),
  (['medic', 'nursing', 'health', 'pharma'], Icons.medical_services_rounded),
  (['engineer', 'control', 'circuit', 'instrument'], Icons.precision_manufacturing_rounded),
];
