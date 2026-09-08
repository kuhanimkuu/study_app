import 'package:flutter_test/flutter_test.dart';
import 'package:study_os_frontend/core/crypto/user_crypto.dart';

/// Regression test for UserCrypto's wire-format compatibility with
/// server/crypto.py's AES-256-GCM implementation. `_goldenCiphertext` was
/// generated once by server/crypto.py itself:
///
///   from server import crypto
///   key = crypto.generate_user_key()
///   crypto.encrypt_for_user(key, 'sk-ant-interop-test-12345')
///
/// If this test ever fails, the two implementations have drifted apart —
/// a BYOK API key encrypted on one side would silently fail to decrypt on
/// the other (see routers/ask.py's ModelConfig.encrypted_api_key).
void main() {
  const goldenKey = 'L0gYVAyg8CnYMWrkoFj-czNK1ESLbuT_pDJhZol3VQs=';
  const goldenCiphertext = 'zs3y7WT1WFKZC9WxEbVhsgCh8ZKBG8uIUodJmLg2QR8jgQw37hFByETwtswMOZcjtN91q-I=';
  const goldenPlaintext = 'sk-ant-interop-test-12345';

  test('decrypts ciphertext produced by server/crypto.py', () async {
    final plaintext = await UserCrypto.decryptForUser(goldenKey, goldenCiphertext);
    expect(plaintext, goldenPlaintext);
  });

  test('round-trips its own ciphertext', () async {
    final ct = await UserCrypto.encryptForUser(goldenKey, 'round-trip-check');
    final plaintext = await UserCrypto.decryptForUser(goldenKey, ct);
    expect(plaintext, 'round-trip-check');
  });

  test('rejects ciphertext decrypted with the wrong key', () async {
    const wrongKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
    expect(
      () => UserCrypto.decryptForUser(wrongKey, goldenCiphertext),
      throwsA(anything),
    );
  });
}
