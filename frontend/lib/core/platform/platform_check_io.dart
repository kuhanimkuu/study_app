import 'dart:io';

/// Native (Android/Windows/etc.) build of the platform check — real
/// dart:io Platform.isAndroid, compiled in for every non-web target via
/// platform_check.dart's conditional export.
bool get isAndroidPlatform => Platform.isAndroid;
