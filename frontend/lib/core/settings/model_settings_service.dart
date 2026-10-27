import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// BYOK model preference (backend/model name/API key), plus the hosted
/// pay-as-you-go tier's provider choice (blueprint Section 42.1) —
/// local-only, per the local-first pivot (see server/main.py's
/// architecture note). The raw BYOK key never leaves the device except as
/// an ephemeral, per-request AES-GCM-encrypted value on the one
/// /api/ask/text call that needs it (see UserCrypto.encryptForUser and
/// ChatScreen's request wiring). `backend == 'hosted'` never stores or
/// sends any key at all — see server/domains/billing/, which holds Study
/// OS's own pooled provider key server-side. Stored in the OS keystore via
/// flutter_secure_storage — same mechanism as the JWT token — keyed per
/// user_id so switching accounts on one device never leaks another user's
/// settings.
class ModelSettingsService extends ChangeNotifier {
  final _storage = const FlutterSecureStorage();

  int? _userId;
  String backend = 'local';
  String? modelName;
  String? apiKey;
  // backend == 'hosted' only. Set (to 'auto') once the student picks Study
  // OS AI; the server chooses the model and ignores the value (2026-10-27).
  String? hostedProvider;

  bool get hasApiKey => apiKey != null && apiKey!.isNotEmpty;

  static const byokProviders = ['deepseek', 'openai', 'anthropic'];

  /// Whether Sage can answer: a provider with its key, or the hosted tier.
  /// The free built-in model isn't available on the server, so "local"
  /// (the default) means AI isn't set up yet (2026-10-21).
  bool get aiReady =>
      (byokProviders.contains(backend) && hasApiKey) || (backend == 'hosted' && hostedProvider != null);

  Future<void> load(int userId) async {
    _userId = userId;
    backend = await _storage.read(key: _key('backend', userId)) ?? 'local';
    modelName = await _storage.read(key: _key('model_name', userId));
    apiKey = await _storage.read(key: _key('api_key', userId));
    hostedProvider = await _storage.read(key: _key('hosted_provider', userId));
    notifyListeners();
  }

  Future<void> save({
    required String backend,
    String? modelName,
    String? apiKey,
    String? hostedProvider,
  }) async {
    final userId = _userId;
    if (userId == null) throw StateError('ModelSettingsService.load(userId) must be called first');

    this.backend = backend;
    this.modelName = modelName;
    this.apiKey = apiKey;
    this.hostedProvider = hostedProvider;

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
    if (hostedProvider != null && hostedProvider.isNotEmpty) {
      await _storage.write(key: _key('hosted_provider', userId), value: hostedProvider);
    } else {
      await _storage.delete(key: _key('hosted_provider', userId));
    }
    notifyListeners();
  }

  /// Called on logout — clears in-memory state only. Deliberately does NOT
  /// wipe the persisted keystore entries, so the same user logging back in
  /// on this device gets their BYOK/hosted settings back without
  /// re-entering them.
  void reset() {
    _userId = null;
    backend = 'local';
    modelName = null;
    apiKey = null;
    hostedProvider = null;
    notifyListeners();
  }

  String _key(String field, int userId) => 'byok_${userId}_$field';
}
