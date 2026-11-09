import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppLockService {
  AppLockService._();

  static final instance = AppLockService._();

  static const _saltKey = 'app_lock_pin_salt_v1';
  static const _hashKey = 'app_lock_pin_hash_v1';
  static const _failuresKey = 'app_lock_failures_v1';
  static const _lockedUntilKey = 'app_lock_locked_until_v1';

  final _storage = const FlutterSecureStorage();
  final _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 310000,
    bits: 256,
  );

  /// PIN must be 6 to 8 ASCII digits, shared by all PIN entry points.
  static bool isValidPinFormat(String pin) =>
      RegExp(r'^[0-9]{6,8}$').hasMatch(pin);

  Future<bool> get isConfigured async =>
      await _storage.read(key: _hashKey) != null;

  Future<Duration> lockoutRemaining() async {
    final value = await _storage.read(key: _lockedUntilKey);
    if (value == null) return Duration.zero;
    final until = DateTime.tryParse(value);
    if (until == null || !until.isAfter(DateTime.now())) {
      await _storage.delete(key: _lockedUntilKey);
      return Duration.zero;
    }
    return until.difference(DateTime.now());
  }

  Future<void> setPin(String pin) async {
    _validatePin(pin);
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final key = await _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );
    final hash = await key.extractBytes();
    await _storage.write(key: _saltKey, value: base64Encode(salt));
    await _storage.write(key: _hashKey, value: base64Encode(hash));
    await _clearFailures();
  }

  Future<bool> verifyPin(String pin) async {
    final remaining = await lockoutRemaining();
    if (remaining > Duration.zero) {
      throw StateError(
        'बहुत बार गलत PIN डाला गया। ${remaining.inSeconds + 1} सेकंड बाद प्रयास करें।',
      );
    }
    final saltValue = await _storage.read(key: _saltKey);
    final hashValue = await _storage.read(key: _hashKey);
    if (saltValue == null || hashValue == null) return false;

    final key = await _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: base64Decode(saltValue),
    );
    final actual = await key.extractBytes();
    final expected = base64Decode(hashValue);
    var difference = actual.length ^ expected.length;
    for (var i = 0; i < min(actual.length, expected.length); i++) {
      difference |= actual[i] ^ expected[i];
    }
    if (difference == 0) {
      await _clearFailures();
      return true;
    }

    final failures =
        (int.tryParse(await _storage.read(key: _failuresKey) ?? '0') ?? 0) + 1;
    await _storage.write(key: _failuresKey, value: failures.toString());
    if (failures >= 5) {
      final exponent = min(failures - 5, 5);
      final seconds = min(30 * (1 << exponent), 900);
      await _storage.write(
        key: _lockedUntilKey,
        value: DateTime.now().add(Duration(seconds: seconds)).toIso8601String(),
      );
    }
    return false;
  }

  Future<void> changePin({
    required String oldPin,
    required String newPin,
  }) async {
    final valid = await verifyPin(oldPin);
    if (!valid) throw StateError('पुराना PIN गलत है।');
    await setPin(newPin);
  }

  Future<void> _clearFailures() async {
    await _storage.delete(key: _failuresKey);
    await _storage.delete(key: _lockedUntilKey);
  }

  void _validatePin(String pin) {
    if (!isValidPinFormat(pin)) {
      throw ArgumentError('PIN 6 से 8 अंकों का होना चाहिए।');
    }
  }
}
