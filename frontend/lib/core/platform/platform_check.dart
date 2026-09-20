// Picks the real dart:io-backed implementation on native targets, and the
// web-safe stub when compiling for the browser (dart:io doesn't exist
// there — importing it directly and unconditionally would break the web
// build entirely, not just misbehave at runtime).
export 'platform_check_stub.dart' if (dart.library.io) 'platform_check_io.dart';
