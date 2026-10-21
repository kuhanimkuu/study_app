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

  final on = ValueNotifier<bool>(true);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      on.value = prefs.getBool(_key) ?? true;
    } catch (_) {
      // Defaults to on.
    }
  }

  Future<void> set(bool value) async {
    on.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}
