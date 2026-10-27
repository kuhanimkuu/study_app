import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether Sage teaches in chat — ends explanations with a quick question
/// and marks the answer — or just answers (2026-10-21). On by default; the
/// chat menu's "Sage checks I understood" switches it. One setting for the
/// main chat and subject chats.
class TutorMode {
  TutorMode._();

  static final instance = TutorMode._();
  static const _key = 'chat_tutor_mode';
  static const _depthKey = 'chat_answer_depth';

  /// How much Sage explains (2026-10-27): "quick" (a paragraph), "full"
  /// (intuition, idea, worked example, common mistakes, related topics) or
  /// "exam" (full plus how it's examined). Sent with every question.
  static const depths = {'quick': 'Quick', 'full': 'Full', 'exam': 'Exam-level'};

  final on = ValueNotifier<bool>(true);
  final depth = ValueNotifier<String>('full');

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      on.value = prefs.getBool(_key) ?? true;
      final saved = prefs.getString(_depthKey);
      depth.value = depths.containsKey(saved) ? saved! : 'full';
    } catch (_) {
      // Defaults: on, full.
    }
  }

  Future<void> setDepth(String value) async {
    depth.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_depthKey, value);
  }

  Future<void> set(bool value) async {
    on.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}
