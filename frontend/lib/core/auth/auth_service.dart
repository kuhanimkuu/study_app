import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../settings/model_settings_service.dart';
import '../storage/local_db.dart';

/// Owns auth state: the JWT token and per-user encryption_key (both
/// persisted in secure, encrypted on-device storage), and the current
/// user's public profile. A ChangeNotifier so AuthGate/AppShell rebuild
/// automatically on login/logout/account updates, no manual plumbing
/// between screens.
///
/// Also the one place that opens/closes the device-local stores on
/// login/logout — LocalDb (chat history, activity events) and
/// ModelSettingsService (BYOK settings) are both scoped per user_id, per
/// the local-first pivot (see server/main.py's architecture note).
class AuthService extends ChangeNotifier {
  AuthService({required this.apiClient, required this.modelSettings});

  final ApiClient apiClient;
  final ModelSettingsService modelSettings;
  final _storage = const FlutterSecureStorage();
  static const _tokenKey = 'auth_token';
  static const _encryptionKeyKey = 'encryption_key';

  Map<String, dynamic>? _user;
  Map<String, dynamic>? get user => _user;
  bool get isAuthenticated => _user != null;

  /// This user's per-device AES-256-GCM key (server/crypto.py), needed to
  /// encrypt a BYOK API key before sending it on any /api/ask/text call —
  /// see UserCrypto.encryptForUser. Returned by the server only at
  /// signup/login (db.auth_user()), never by routine calls like /me.
  String? _encryptionKey;
  String? get encryptionKey => _encryptionKey;

  bool _initialized = false;
  bool get initialized => _initialized;

  /// Call once at app startup — restores a saved token, if any, and
  /// verifies it's still valid by fetching the current user rather than
  /// trusting a possibly-expired token blindly.
  ///
  /// The whole body is wrapped in try/catch, and every await here has its
  /// own SHORT timeout — deliberately much shorter than ApiClient's usual
  /// 60s (which has to stay generous for slow LLM requests). A cold
  /// startup check of "is my saved login still valid" should feel
  /// near-instant; if the network is genuinely unreachable (a dropped
  /// `adb reverse` tunnel on a real-device dev setup — see
  /// server/README.md — was the real case this was found from), the user
  /// should land on the login screen within a few seconds, not stare at
  /// a spinner for up to a minute waiting for ApiClient's own timeout.
  /// Secure storage can also throw outright (no platform channel
  /// registered, e.g. under `flutter test`) or simply never resolve (a
  /// stuck native keystore call) — letting either case go unhandled would
  /// leave `_initialized` false forever, stranding AuthGate on its
  /// loading spinner instead of falling back to a normal logged-out state.
  static const _startupCheckTimeout = Duration(seconds: 8);

  Future<void> restoreSession() async {
    try {
      final token = await _storage.read(key: _tokenKey).timeout(_startupCheckTimeout);
      if (token != null) {
        apiClient.token = token;
        try {
          _user = await apiClient.me().timeout(_startupCheckTimeout);
          _encryptionKey = await _storage.read(key: _encryptionKeyKey).timeout(_startupCheckTimeout);
          await _openLocalStores();
        } catch (e) {
          // Treat as logged out for now either way, but only WIPE the
          // saved token on a genuine server-confirmed rejection (401) —
          // a timeout/unreachable-network failure (e.g. a dropped `adb
          // reverse` tunnel) leaves it on disk so a later successful
          // restoreSession() can still use it, instead of forcing a real
          // re-login over what was just a transient connectivity blip.
          apiClient.token = null;
          if (e is ApiException && e.statusCode == 401) {
            await _storage.delete(key: _tokenKey);
          }
        }
      }
    } catch (_) {
      // secure storage unavailable or unresponsive — fall back to logged-out.
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> signup({required String email, required String password, String? displayName}) async {
    final result = await apiClient.signup(email: email, password: password, displayName: displayName);
    await _applyAuthResult(result);
  }

  Future<void> login({required String email, required String password}) async {
    final result = await apiClient.login(email: email, password: password);
    await _applyAuthResult(result);
  }

  Future<void> _applyAuthResult(Map<String, dynamic> result) async {
    final token = result['token'] as String;
    apiClient.token = token;
    await _storage.write(key: _tokenKey, value: token);

    _user = result['user'] as Map<String, dynamic>;
    final encKey = _user?['encryption_key'] as String?;
    if (encKey != null) {
      _encryptionKey = encKey;
      await _storage.write(key: _encryptionKeyKey, value: encKey);
    }

    await _openLocalStores();
    notifyListeners();
  }

  Future<void> _openLocalStores() async {
    final userId = _user?['id'] as int?;
    if (userId == null) return;
    await LocalDb.instance.open(userId);
    await modelSettings.load(userId);
  }

  Future<void> logout() async {
    apiClient.token = null;
    _user = null;
    _encryptionKey = null;
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _encryptionKeyKey);
    await LocalDb.instance.close();
    modelSettings.reset();
    notifyListeners();
  }

  Future<void> updateDisplayName(String displayName) async {
    _user = await apiClient.updateAccount(displayName: displayName);
    notifyListeners();
  }
}
