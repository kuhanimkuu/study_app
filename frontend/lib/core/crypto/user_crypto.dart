import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Dart side of the per-user AES-256-GCM scheme in server/crypto.py — MUST
/// match its wire format exactly: base64url(12-byte nonce || AES-GCM
/// ciphertext with the 16-byte tag appended). This is what lets the device
/// encrypt a BYOK API key with the same `encryption_key` the server handed
/// back at signup/login, send it along on one request, and have
/// crypto.decrypt_for_user() on the other end recover it — see
/// routers/ask.py's ModelConfig.encrypted_api_key.
class UserCrypto {
  static final _algorithm = AesGcm.with256bits();
  static const _nonceBytes = 12;
  static const _macBytes = 16;

  static Future<String> encryptForUser(String keyB64, String plaintext) async {
    final key = SecretKey(base64Url.decode(_pad(keyB64)));
    final secretBox = await _algorithm.encrypt(utf8.encode(plaintext), secretKey: key);
    final wire = Uint8List.fromList([
      ...secretBox.nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
    return base64Url.encode(wire);
  }

  static Future<String> decryptForUser(String keyB64, String tokenB64) async {
    final key = SecretKey(base64Url.decode(_pad(keyB64)));
    final raw = base64Url.decode(_pad(tokenB64));
    if (raw.length < _nonceBytes + _macBytes) {
      throw ArgumentError('ciphertext too short to contain a nonce and MAC');
    }
    final nonce = raw.sublist(0, _nonceBytes);
    final cipherText = raw.sublist(_nonceBytes, raw.length - _macBytes);
    final mac = Mac(raw.sublist(raw.length - _macBytes));
    final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
    final clear = await _algorithm.decrypt(secretBox, secretKey: key);
    return utf8.decode(clear);
  }

  /// `base64.urlsafe_b64encode` on the Python side always pads; this just
  /// defends against any caller that hands over an unpadded string.
  static String _pad(String b64) {
    final remainder = b64.length % 4;
    if (remainder == 0) return b64;
    return b64 + '=' * (4 - remainder);
  }
}
