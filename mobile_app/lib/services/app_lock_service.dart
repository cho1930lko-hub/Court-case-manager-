import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppLockService {
  AppLockService._();
  static final instance = AppLockService._();
  static const _saltKey = 'app_lock_pin_salt_v1';
  static const _hashKey = 'app_lock_pin_hash_v1';
  final _storage = const FlutterSecureStorage();
  final _kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 310000, bits: 256);

  Future<bool> get isConfigured async => await _storage.read(key: _hashKey) != null;

  Future<void> setPin(String pin) async {
    if (!RegExp(r'^\d{6,8}$').hasMatch(pin)) {
      throw ArgumentError('PIN 6 से 8 अंकों का होना चाहिए।');
    }
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final key = await _kdf.deriveKey(secretKey: SecretKey(utf8.encode(pin)), nonce: salt);
    final hash = await key.extractBytes();
    await _storage.write(key: _saltKey, value: base64Encode(salt));
    await _storage.write(key: _hashKey, value: base64Encode(hash));
  }

  Future<bool> verifyPin(String pin) async {
    final saltValue = await _storage.read(key: _saltKey);
    final hashValue = await _storage.read(key: _hashKey);
    if (saltValue == null || hashValue == null) return false;
    final key = await _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)), nonce: base64Decode(saltValue),
    );
    final actual = await key.extractBytes();
    final expected = base64Decode(hashValue);
    if (actual.length != expected.length) return false;
    var difference = 0;
    for (var i = 0; i < actual.length; i++) { difference |= actual[i] ^ expected[i]; }
    return difference == 0;
  }
}
