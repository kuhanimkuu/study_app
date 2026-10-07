/// The hosted backend (Render, temporary stand-in until HelioHost) —
/// reachable from any device/platform with no LAN/emulator-alias/adb
/// setup, unlike the old per-platform localhost defaults (127.0.0.1,
/// 10.0.2.2 for the Android emulator, ...). Still editable in the app
/// (AccountScreen / server_settings_dialog) for pointing back at a local
/// dev server when actually developing against it.
///
/// A build can bake in a different default with
/// `--dart-define=STUDY_OS_BASE_URL=...` — the local Windows desktop build
/// (desktop/build_desktop.ps1) uses this to point at http://127.0.0.1:8000
/// so it talks to the backend running on the same PC.
const _baseUrlOverride = String.fromEnvironment('STUDY_OS_BASE_URL');

String defaultBaseUrl() =>
    _baseUrlOverride.isNotEmpty ? _baseUrlOverride : 'https://study-os-backend-iik8.onrender.com';
