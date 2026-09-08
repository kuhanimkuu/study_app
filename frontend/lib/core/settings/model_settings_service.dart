import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// BYOK model preference (backend/model name/API key) — local-only, per
/// the local-first pivot (see server/main.py's architecture note). The raw
/// key never leaves the device except as an ephemeral, per-request
/// AES-GCM-encrypted value on the one /api/ask/text call that needs it
/// (see UserCrypto.encryptForUser and ChatScreen's request wiring).
/// Stored in the OS keystore via flutter_secure_storage — same mechanism
/// as the JWT token — keyed per user_id so switching accounts on one
/// device never leaks another user's key.
class ModelSettingsService extends ChangeNotifier {
  final _storage = const FlutterSecureStorage();

  int? _userId;
  String backend = 'local';
  String? modelName;
  String? apiKey;

  bool get hasApiKey => apiKey != null && apiKey!.isNotEmpty;

  Future<void> load(int userId) async {
    _userId = userId;
    backend = await _storage.read(key: _key('backend', userId)) ?? 'local';
    modelName = await _storage.read(key: _key('model_name', userId));
    apiKey = await _storage.read(key: _key('api_key', userId));
    notifyListeners();
  }

  Future<void> save({required String backend, String? modelName, String? apiKey}) async {
    final userId = _userId;
    if (userId == null) throw StateError('ModelSettingsService.load(userId) must be called first');

    this.backend = backend;
    this.modelName = modelName;
    this.apiKey = apiKey;

    await _storage.write(key: _key('backend', userId), value: backend);
    if (modelName != null && modelName.isNotEmpty) {
      await _storage.write(key: _key('model_name', userId), value: modelName);
    } else {
      await _storage.delete(key: _key('model_name', userId));
    }
    if (apiKey != null && apiKey.isNotEmpty) {
      await _storage.write(key: _key('api_key', userId), value: apiKey);
    } else {
      await _storage.delete(key: _key('api_key', userId));
    }
    notifyListeners();
  }

  /// Called on logout — clears in-memory state only. Deliberately does NOT
  /// wipe the persisted keystore entries, so the same user logging back in
  /// on this device gets their BYOK settings back without re-entering them.
  void reset() {
    _userId = null;
    backend = 'local';
    modelName = null;
    apiKey = null;
    notifyListeners();
  }

  String _key(String field, int userId) => 'byok_${userId}_$field';
}
