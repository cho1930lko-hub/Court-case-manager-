import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

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
    await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
    final dbPath = await LocalDatabase.instance.databasePath();
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) throw StateError('Database file not found');

    final archive = Archive();
    final dbBytes = await dbFile.readAsBytes();
    archive.addFile(ArchiveFile('database/court_case_manager.db', dbBytes.length, dbBytes));

    final appDir = await getApplicationDocumentsDirectory();
    final docsDir = Directory(p.join(appDir.path, 'case_documents'));
    if (await docsDir.exists()) {
      await for (final entity in docsDir.list(recursive: true, followLinks: false)) {
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

  Future<void> restoreBackup(Uint8List fileBytes, String password) async {
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
    const sqliteHeader = 'SQLite format 3\u0000';
    if (dbBytes.length < 100 ||
        utf8.decode(dbBytes.sublist(0, 16), allowMalformed: true) != sqliteHeader) {
      throw const FormatException('Backup database की जाँच असफल हुई।');
    }

    // Validate the restored DB in a temporary file before touching current data.
    final tempRoot = await getTemporaryDirectory();
    final validationPath = p.join(tempRoot.path, 'ccm_restore_validation.db');
    final validationFile = File(validationPath);
    if (await validationFile.exists()) await validationFile.delete();
    await validationFile.writeAsBytes(dbBytes, flush: true);
    Database? validationDb;
    try {
      validationDb = await openDatabase(validationPath, readOnly: true);
      final check = await validationDb.rawQuery('PRAGMA integrity_check');
      if (check.isEmpty || check.first.values.first != 'ok') {
        throw const FormatException('Database integrity check असफल हुई।');
      }
    } finally {
      await validationDb?.close();
      if (await validationFile.exists()) await validationFile.delete();
    }

    final appDir = await getApplicationDocumentsDirectory();
    final staging = Directory(p.join(appDir.path, 'case_documents_restore_tmp'));
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);

    for (final entry in archive.files) {
      if (!entry.isFile || !entry.name.startsWith('case_documents/')) continue;
      final relative = p.normalize(entry.name);
      if (p.isAbsolute(relative) || relative.split(p.separator).contains('..')) {
        throw const FormatException('Backup में असुरक्षित file path मिला।');
      }
      final out = File(p.join(appDir.path, 'case_documents_restore_tmp',
          p.relative(relative, from: 'case_documents')));
      await out.parent.create(recursive: true);
      await out.writeAsBytes(entry.content as List<int>, flush: true);
    }

    // Close SQLite before replacing its file; keep a rollback copy until swap completes.
    final currentPath = await LocalDatabase.instance.databasePath();
    final currentFile = File(currentPath);
    final rollbackPath = '$currentPath.restore_previous';
    if (await currentFile.exists()) await currentFile.copy(rollbackPath);
    try {
      await LocalDatabase.instance.closeForRestore();
      for (final suffix in ['', '-wal', '-shm']) {
        final old = File('$currentPath$suffix');
        if (await old.exists()) await old.delete();
      }
      await File(currentPath).writeAsBytes(dbBytes, flush: true);

      final liveDocs = Directory(p.join(appDir.path, 'case_documents'));
      if (await liveDocs.exists()) await liveDocs.delete(recursive: true);
      if (await staging.exists()) await staging.rename(liveDocs.path);
      await LocalDatabase.instance.database; // Re-open and verify the restored DB.
      if (await File(rollbackPath).exists()) await File(rollbackPath).delete();
    } catch (_) {
      if (await File(rollbackPath).exists()) {
        for (final suffix in ['', '-wal', '-shm']) {
          final sidecar = File('$currentPath$suffix');
          if (await sidecar.exists()) await sidecar.delete();
        }
        await File(rollbackPath).copy(currentPath);
      }
      rethrow;
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
