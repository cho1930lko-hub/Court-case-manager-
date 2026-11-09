import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'secure_database_key.dart';
import 'backup_path_validator.dart';

import '../data/local_database.dart';

/// Password-encrypted full backup (SQLite database + app-managed case files).
/// Uses PBKDF2-HMAC-SHA256 and AES-256-GCM authenticated encryption.
class SecureBackupService {
  SecureBackupService._();
  static final instance = SecureBackupService._();

  static const _format = 'CCM-SECURE-BACKUP';
  static const _iterations = 310000;
  final _cipher = AesGcm.with256bits();

  Future<Uint8List> createBackup(String password) async {
    _validatePassword(password);
    final db = await LocalDatabase.instance.database;
    final checkpoint = await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    if (checkpoint.isNotEmpty && (checkpoint.first['busy'] as int? ?? 0) != 0) {
      throw StateError('Database checkpoint busy है; backup दोबारा प्रयास करें।');
    }
    final dbPath = await LocalDatabase.instance.databasePath();
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) throw StateError('Database file not found');

    final archive = Archive();
    final dbBytes = await dbFile.readAsBytes();
    archive.addFile(ArchiveFile('database/court_case_manager.db', dbBytes.length, dbBytes));
    final databaseKey = await SecureDatabaseKey.instance.read();
    if (databaseKey == null) throw StateError('Database encryption key is unavailable');
    final keyBytes = utf8.encode(databaseKey);
    archive.addFile(ArchiveFile('database/sqlcipher_key.txt', keyBytes.length, keyBytes));

    final appDir = await getApplicationDocumentsDirectory();
    // Back up every app-managed attachment directory. Evidence files are
    // stored separately from case_documents and must travel with the database.
    for (final rootName in const ['case_documents', 'evidence']) {
      final managedDir = Directory(p.join(appDir.path, rootName));
      if (!await managedDir.exists()) continue;
      await for (final entity in managedDir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final relative = p.relative(entity.path, from: appDir.path).replaceAll('\\', '/');
          final bytes = await entity.readAsBytes();
          archive.addFile(ArchiveFile(relative, bytes.length, bytes));
        }
      }
    }

    final zipped = ZipEncoder().encode(archive);
    if (zipped == null || zipped.isEmpty) throw StateError('Backup archive could not be created');
    final salt = _cipher.newNonce();
    final nonce = _cipher.newNonce();
    final key = await _deriveKey(password, salt);
    final box = await _cipher.encrypt(zipped, secretKey: key, nonce: nonce);
    final envelope = <String, Object>{
      'format': _format,
      'version': 1,
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': _iterations,
      'cipher': 'AES-256-GCM',
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'ciphertext': base64Encode(box.cipherText),
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
  }

  Future<void> restoreBackup(Uint8List fileBytes, String password, {bool allowUninitializedDatabase = false}) async {
    _validatePassword(password);
    final decoded = jsonDecode(utf8.decode(fileBytes));
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != _format || decoded['version'] != 1) {
      throw const FormatException('यह मान्य Court Case Manager backup नहीं है।');
    }
    if (decoded['kdf'] != 'PBKDF2-HMAC-SHA256' ||
        decoded['cipher'] != 'AES-256-GCM' ||
        decoded['iterations'] != _iterations) {
      throw const FormatException('Backup का encryption format समर्थित नहीं है।');
    }

    final salt = base64Decode(decoded['salt'] as String);
    final nonce = base64Decode(decoded['nonce'] as String);
    final mac = Mac(base64Decode(decoded['mac'] as String));
    final cipherText = base64Decode(decoded['ciphertext'] as String);
    final key = await _deriveKey(password, salt);
    final clear = await _cipher.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac), secretKey: key,
    );

    final archive = ZipDecoder().decodeBytes(clear);
    final dbEntry = archive.findFile('database/court_case_manager.db');
    if (dbEntry == null || !dbEntry.isFile) {
      throw const FormatException('Backup में database मौजूद नहीं है।');
    }
    final dbBytes = Uint8List.fromList(dbEntry.content as List<int>);
    final keyEntry = archive.findFile('database/sqlcipher_key.txt');
    if (keyEntry == null || !keyEntry.isFile) {
      throw const FormatException('Backup में database encryption key मौजूद नहीं है।');
    }
    final backupDatabaseKey = utf8.decode(keyEntry.content as List<int>);
    if (base64Url.decode(backupDatabaseKey).length != 32) {
      throw const FormatException('Backup database key अमान्य है।');
    }

    // Validate the encrypted DB with its bundled key before touching current data.
    final tempRoot = await getTemporaryDirectory();
    final validationPath = p.join(tempRoot.path, 'ccm_restore_validation.db');
    final validationFile = File(validationPath);
    for (final suffix in ['', '-wal', '-shm']) {
      final stale = File('$validationPath$suffix');
      if (await stale.exists()) await stale.delete();
    }
    await validationFile.writeAsBytes(dbBytes, flush: true);
    Database? validationDb;
    try {
      validationDb = await openDatabase(validationPath, password: backupDatabaseKey, readOnly: true);
      final check = await validationDb.rawQuery('PRAGMA integrity_check');
      if (check.isEmpty || check.first.values.first != 'ok') {
        throw const FormatException('Encrypted database integrity check असफल हुई।');
      }
      final tables = await validationDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
      if (tables.isEmpty) throw const FormatException('Backup database खाली या अमान्य है।');
    } finally {
      await validationDb?.close();
      for (final suffix in ['', '-wal', '-shm']) {
        final stale = File('$validationPath$suffix');
        if (await stale.exists()) await stale.delete();
      }
    }

    final appDir = await getApplicationDocumentsDirectory();
    final staging = Directory(p.join(appDir.path, 'managed_files_restore_tmp'));
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);

    // Extract only the two known managed roots. Reject traversal and malformed
    // paths before writing any decrypted attachment to disk.
    try {
      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        if (!entry.name.startsWith('case_documents/') &&
            !entry.name.startsWith('evidence/')) continue;
        final safeRelative = safeManagedFileRelativePath(entry.name);
        final out = File(p.join(staging.path, safeRelative));
        await out.parent.create(recursive: true);
        await out.writeAsBytes(entry.content as List<int>, flush: true);
      }
      for (final rootName in const ['case_documents', 'evidence']) {
        await Directory(p.join(staging.path, rootName)).create(recursive: true);
      }
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }

    // Keep rollback copies of both managed directories and the encrypted DB
    // until the restored database has passed its final integrity check.
    final currentPath = await LocalDatabase.instance.databasePath();
    final currentFile = File(currentPath);
    final hadCurrentDatabase = await currentFile.exists();
    final rollbackPath = '$currentPath.restore_previous';
    final previousDatabaseKey = await SecureDatabaseKey.instance.read();
    final managedRoots = const ['case_documents', 'evidence'];
    final oldPaths = <String, String>{
      for (final rootName in managedRoots)
        rootName: p.join(appDir.path, '${rootName}_restore_previous'),
    };
    final movedOldRoots = <String>[];
    final installedNewRoots = <String>[];

    try {
      if (!allowUninitializedDatabase) {
        final liveDb = await LocalDatabase.instance.database;
        final checkpoint = await liveDb.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
        if (checkpoint.isNotEmpty && (checkpoint.first['busy'] as int? ?? 0) != 0) {
          throw StateError('Database checkpoint busy है; restore सुरक्षित रूप से शुरू नहीं किया जा सकता।');
        }
      }
      if (await currentFile.exists()) await currentFile.copy(rollbackPath);

      for (final rootName in managedRoots) {
        final old = Directory(oldPaths[rootName]!);
        if (await old.exists()) await old.delete(recursive: true);
        final live = Directory(p.join(appDir.path, rootName));
        if (await live.exists()) {
          await live.rename(old.path);
          movedOldRoots.add(rootName);
        }
      }

      await LocalDatabase.instance.closeForRestore();
      for (final suffix in ['', '-wal', '-shm']) {
        final sidecar = File('$currentPath$suffix');
        if (await sidecar.exists()) await sidecar.delete();
      }
      await File(currentPath).writeAsBytes(dbBytes, flush: true);
      await SecureDatabaseKey.instance.replace(backupDatabaseKey);

      for (final rootName in managedRoots) {
        final stagedRoot = Directory(p.join(staging.path, rootName));
        final liveRoot = Directory(p.join(appDir.path, rootName));
        await stagedRoot.rename(liveRoot.path);
        installedNewRoots.add(rootName);
      }

      final restoredDb = await LocalDatabase.instance.database;
      final check = await restoredDb.rawQuery('PRAGMA integrity_check');
      if (check.isEmpty || check.first.values.first != 'ok') {
        throw const FormatException('Restored database की अंतिम जाँच असफल हुई।');
      }

      // Restore is committed after integrity_check. Cleanup failures must
      // not trigger rollback after any rollback copy has already been removed.
      for (final rootName in movedOldRoots) {
        final old = Directory(oldPaths[rootName]!);
        try {
          if (await old.exists()) await old.delete(recursive: true);
        } catch (_) {
          // Leave the previous copy for manual/next-start cleanup; restored
          // records and their new attachments are already valid.
        }
      }
      try {
        if (await File(rollbackPath).exists()) await File(rollbackPath).delete();
      } catch (_) {
        // A stale encrypted rollback file is safer than undoing a valid restore.
      }
    } catch (_) {
      await LocalDatabase.instance.closeForRestore();
      for (final suffix in ['', '-wal', '-shm']) {
        final sidecar = File('$currentPath$suffix');
        if (await sidecar.exists()) await sidecar.delete();
      }
      final rollbackFile = File(rollbackPath);
      if (await rollbackFile.exists()) {
        await rollbackFile.copy(currentPath);
      } else if (!hadCurrentDatabase) {
        // Recovery restore on a fresh/uninitialized install has no previous
        // database to copy back. Never leave a partially installed DB behind.
        final partialDatabase = File(currentPath);
        if (await partialDatabase.exists()) await partialDatabase.delete();
      }
      if (previousDatabaseKey != null) {
        await SecureDatabaseKey.instance.replace(previousDatabaseKey);
      } else {
        // A missing pre-restore key must remain missing after a failed restore.
        await SecureDatabaseKey.instance.clear();
      }
      for (final rootName in installedNewRoots) {
        final live = Directory(p.join(appDir.path, rootName));
        if (await live.exists()) await live.delete(recursive: true);
      }
      for (final rootName in movedOldRoots.reversed) {
        final old = Directory(oldPaths[rootName]!);
        final live = Directory(p.join(appDir.path, rootName));
        if (await old.exists()) {
          if (await live.exists()) await live.delete(recursive: true);
          await old.rename(live.path);
        }
      }
      rethrow;
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Future<SecretKey> _deriveKey(String password, List<int> salt) {
    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _iterations,
      bits: 256,
    );
    return kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }

  void _validatePassword(String password) {
    if (password.length < 12) {
      throw ArgumentError('Backup password कम से कम 12 अक्षरों का होना चाहिए।');
    }
  }
}
