import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api/api_client.dart';

/// Sends the app's own crashes to Study OS's server (2026-10-20) — POST
/// /api/v1/client-errors, see server/domains/diagnostics/. Only the error,
/// where in the code it happened, the app version and the platform; never
/// notes, chats or what the student typed (messages are cut short, since
/// an error's text can quote the data it choked on).
///
/// Quiet by design: off in debug builds, network failures are skipped (a
/// phone without signal isn't a bug), each distinct error is sent once per
/// app run, at most [_maxPerRun] per run, and a failed send is dropped.
class ErrorReporter {
  ErrorReporter({required this.apiClient, Future<String> Function()? appVersion, this.enabled = !kDebugMode})
      : _appVersion = appVersion ?? _packageVersion;

  final ApiClient apiClient;
  final bool enabled;
  final Future<String> Function() _appVersion;

  static const _maxPerRun = 10;
  static const _maxMessage = 500;
  final _sent = <String>{};

  static Future<String> _packageVersion() async {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  }

  /// Routes Flutter framework errors and uncaught async errors here, while
  /// keeping Flutter's own console output.
  void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      report(details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack);
      return false; // still logged the default way
    };
  }

  static const _networkErrors = ['SocketException', 'ClientException', 'TimeoutException', 'HandshakeException', 'HttpException'];

  /// Whether [error] is worth a report — see the class comment.
  static bool shouldReport(Object error) {
    final type = error.runtimeType.toString();
    return !_networkErrors.any(type.contains);
  }

  Future<void> report(Object error, StackTrace? stack) async {
    if (!enabled || !shouldReport(error) || _sent.length >= _maxPerRun) return;
    final message = '${error.runtimeType}: $error';
    final stackText = (stack ?? StackTrace.empty).toString();
    final key = '$message\n${stackText.split('\n').first}';
    if (!_sent.add(key)) return;
    try {
      await apiClient.reportClientError(
        message: message.length > _maxMessage ? '${message.substring(0, _maxMessage)}…' : message,
        stack: stackText,
        appVersion: await _appVersion(),
        platform: defaultTargetPlatform.name,
      );
    } catch (_) {
      // Reporting must never cause a second error.
    }
  }
}
