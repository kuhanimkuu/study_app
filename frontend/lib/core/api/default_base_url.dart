/// The hosted backend (Render, temporary stand-in until HelioHost) —
/// reachable from any device/platform with no LAN/emulator-alias/adb
/// setup, unlike the old per-platform localhost defaults (127.0.0.1,
/// 10.0.2.2 for the Android emulator, ...). Still editable in the app
/// (AccountScreen / server_settings_dialog) for pointing back at a local
/// dev server when actually developing against it.
String defaultBaseUrl() => 'https://study-os-backend-iik8.onrender.com';
