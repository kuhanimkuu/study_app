/// Web build of the platform check — dart:io (and therefore Platform.isAndroid)
/// doesn't exist in a browser, so this stub is what gets compiled in for web
/// (see platform_check.dart's conditional export).
bool get isAndroidPlatform => false;
