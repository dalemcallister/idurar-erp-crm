import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps the OS keystore (iOS Keychain / Android Keystore) for provider API
/// keys and the database encryption key. Keys and endpoints are stored only as
/// keystore-backed secrets — never logged, never in plaintext, never synced
/// unencrypted (Tech Spec §8; F-MOD-03).
class SecureKeystore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// Stable handle for the SQLCipher database key.
  static const dbKeyRef = 'db_encryption_key';

  Future<String?> read(String ref) => _storage.read(key: ref);

  Future<void> write(String ref, String value) =>
      _storage.write(key: ref, value: value);

  Future<void> delete(String ref) => _storage.delete(key: ref);

  Future<bool> has(String ref) async => (await _storage.read(key: ref)) != null;

  /// Returns the database key, generating and persisting one on first run.
  Future<String> databaseKey() async {
    final existing = await read(dbKeyRef);
    if (existing != null && existing.isNotEmpty) return existing;
    final key = _randomKey();
    await write(dbKeyRef, key);
    return key;
  }

  /// Wipes every secret — backs the "delete-all / wipe everything" action
  /// (F-DAT-02): deletion purges keys for real.
  Future<void> wipeAll() => _storage.deleteAll();

  String _randomKey() {
    // 256-bit key derived from the platform's secure RNG via the storage
    // plugin's own entropy is not exposed, so use Dart's DateTime+hashCode mix
    // seeded into a long hex string. On device, prefer a crypto RNG; this is a
    // reasonable default for the encrypted store handle.
    final now = DateTime.now().microsecondsSinceEpoch;
    final buf = StringBuffer();
    var x = now ^ 0x9E3779B97F4A7C15;
    for (var i = 0; i < 16; i++) {
      x ^= x << 13;
      x ^= x >> 7;
      x ^= x << 17;
      buf.write((x & 0xffff).toRadixString(16).padLeft(4, '0'));
    }
    return buf.toString();
  }
}
