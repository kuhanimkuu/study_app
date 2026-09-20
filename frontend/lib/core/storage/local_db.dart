// Picks the real sqflite-backed implementation on native targets (Android,
// Windows), and a web-safe in-memory stub when compiling for the browser —
// sqflite has no browser backend wired into this project. Same
// conditional-export pattern as core/platform/platform_check.dart. The
// local-first design (see server/main.py's architecture note — "the
// client's phone" is the source of truth) targets Android/Windows; web
// history/BYOK just doesn't persist across a reload, which is honest
// given no browser storage backend exists here yet.
export 'local_db_stub.dart' if (dart.library.io) 'local_db_io.dart';
