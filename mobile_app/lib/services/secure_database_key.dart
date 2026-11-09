import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureDatabaseKey {
  SecureDatabaseKey._();
  static final instance = SecureDatabaseKey._();
  static const _keyName = 'court_case_manager_sqlcipher_key_v1';
  final _storage = const FlutterSecureStorage();

  Future<String?> read() => _storage.read(key: _keyName);

  Future<String> create() async {
    final existing = await read();
    if (existing != null) return existing;
    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final key = base64UrlEncode(bytes);
    await _storage.write(key: _keyName, value: key);
    return key;
  }

  Future<void> replace(String key) async {
    final bytes = base64Url.decode(key);
    if (bytes.length != 32) throw const FormatException('Invalid database key');
    await _storage.write(key: _keyName, value: key);
  }

  /// Removes the SQLCipher key when rolling back a restore that began
  /// without a pre-existing database key.
  Future<void> clear() => _storage.delete(key: _keyName);
}
