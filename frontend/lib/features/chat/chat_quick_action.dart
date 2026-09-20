/// What Home's quick-actions row (Ask/PDF/Scan/Voice) asks Chat to do once
/// `AppShell` switches to the Chat tab — a one-shot signal delivered via a
/// `ValueNotifier<ChatQuickAction?>` shared between `HomeScreen` and
/// `ChatScreen` (see `AppShell`'s doc comment for why: `ChatScreen` is a
/// persistent `IndexedStack` child, not rebuilt on tab switch, so it needs
/// to react to a value change rather than an initial constructor param).
enum ChatQuickAction {
  /// Focuses the text field so the keyboard is up and ready to type.
  ask,
  pdf,
  scan,
  voice,
}
