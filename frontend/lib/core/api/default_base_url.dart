import 'package:flutter/foundation.dart' show kIsWeb;

import '../platform/platform_check.dart';

/// Platform-aware default server URL. Windows desktop and web both reach
/// the dev server directly at 127.0.0.1; an Android emulator's 127.0.0.1
/// refers to the emulator itself, not the host machine — 10.0.2.2 is the
/// documented special alias Android emulators use to reach the host.
/// Wrong for a real Android device on a LAN (needs the host's actual IP),
/// which is exactly why this is editable in the app (AccountScreen /
/// server_settings_dialog), not hardcoded.
String defaultBaseUrl() {
  if (kIsWeb) return 'http://127.0.0.1:8000';
  return isAndroidPlatform ? 'http://10.0.2.2:8000' : 'http://127.0.0.1:8000';
}
