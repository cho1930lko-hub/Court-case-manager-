import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:court_case_manager/services/app_lock_service.dart';
import 'package:court_case_manager/services/secure_backup_service.dart';
import 'package:court_case_manager/services/backup_path_validator.dart';

void main() {
  group('PIN format (shared by setup, unlock and change-PIN)', () {
    test('accepts 6 to 8 ASCII digits', () {
      for (final pin in ['123456', '1234567', '12345678']) {
        expect(AppLockService.isValidPinFormat(pin), isTrue, reason: pin);
      }
    });

    test('rejects wrong length, letters, spaces, backslash and non-ASCII digits', () {
      for (final pin in ['', '12345', '123456789', '12ab56', '123 456', r'\\d123456', '१२३४५६', '123456\\n']) {
        expect(AppLockService.isValidPinFormat(pin), isFalse, reason: pin);
      }
    });
  });

  group('AppLockService PIN validation', () {
    test('rejects PIN shorter than six digits', () async {
      await expectLater(
        AppLockService.instance.setPin('12345'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects non-numeric PIN', () async {
      await expectLater(
        AppLockService.instance.setPin('12ab56'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects PIN longer than eight digits', () async {
      await expectLater(
        AppLockService.instance.setPin('123456789'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Backup document path validation', () {
    test('accepts files under both managed attachment roots', () {
      expect(safeCaseDocumentRelativePath('case_documents/case-1/order.pdf'),
          'case-1/order.pdf');
      expect(safeManagedFileRelativePath('evidence/case-1/seizure-photo.jpg'),
          'evidence/case-1/seizure-photo.jpg');
    });

    test('rejects unknown roots, empty segments and traversal in evidence paths', () {
      for (final path in [
        'other/case-1/file.pdf',
        'evidence/../outside.pdf',
        'evidence/case-1/../../outside.pdf',
        'evidence//file.pdf',
        r'evidence\\case-1\\..\\..\\outside.pdf',
        '/evidence/case-1/file.pdf',
      ]) {
        expect(() => safeManagedFileRelativePath(path),
            throwsA(isA<FormatException>()), reason: path);
      }
    });

    test('rejects parent traversal that normalizes outside the document root', () {
      expect(
        () => safeCaseDocumentRelativePath('case_documents/../outside.txt'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects nested traversal and absolute paths', () {
      expect(
        () => safeCaseDocumentRelativePath('case_documents/a\\\\..\\\\..\\\\outside.txt'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => safeCaseDocumentRelativePath('/case_documents/outside.txt'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('SecureBackupService password validation', () {
    test('rejects password shorter than twelve characters before file access', () async {
      await expectLater(
        SecureBackupService.instance.createBackup('short-pass'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Secure backup restore input validation', () {
    test('rejects a corrupt or non-JSON backup before touching local files', () async {
      await expectLater(
        SecureBackupService.instance.restoreBackup(
          Uint8List.fromList(utf8.encode('not-json')),
          'a-strong-backup-password',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a backup with an unsupported envelope', () async {
      await expectLater(
        SecureBackupService.instance.restoreBackup(
          Uint8List.fromList(utf8.encode(jsonEncode({
            'format': 'NOT-A-COURT-BACKUP',
            'version': 1,
          }))),
          'a-strong-backup-password',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a validly encrypted archive that has no database entry', () async {
      const password = 'correct-horse-battery';
      final cipher = AesGcm.with256bits();
      final salt = cipher.newNonce();
      final nonce = cipher.newNonce();
      final derived = await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 310000,
        bits: 256,
      ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);

      final archive = Archive();
      final payload = utf8.encode('not a database backup');
      archive.addFile(ArchiveFile('unexpected.txt', payload.length, payload));
      final zipped = ZipEncoder().encode(archive)!;
      final encrypted = await cipher.encrypt(zipped, secretKey: derived, nonce: nonce);
      final envelope = jsonEncode({
        'format': 'CCM-SECURE-BACKUP',
        'version': 1,
        'kdf': 'PBKDF2-HMAC-SHA256',
        'iterations': 310000,
        'cipher': 'AES-256-GCM',
        'salt': base64Encode(salt),
        'nonce': base64Encode(encrypted.nonce),
        'mac': base64Encode(encrypted.mac.bytes),
        'ciphertext': base64Encode(encrypted.cipherText),
      });

      await expectLater(
        SecureBackupService.instance.restoreBackup(
          Uint8List.fromList(utf8.encode(envelope)),
          password,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a backup encrypted with a different password', () async {
      const originalPassword = 'original-backup-password';
      final cipher = AesGcm.with256bits();
      final salt = cipher.newNonce();
      final nonce = cipher.newNonce();
      final derived = await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 310000,
        bits: 256,
      ).deriveKey(
        secretKey: SecretKey(utf8.encode(originalPassword)),
        nonce: salt,
      );
      final encrypted = await cipher.encrypt(
        utf8.encode('authenticated test payload'),
        secretKey: derived,
        nonce: nonce,
      );
      final envelope = jsonEncode({
        'format': 'CCM-SECURE-BACKUP',
        'version': 1,
        'kdf': 'PBKDF2-HMAC-SHA256',
        'iterations': 310000,
        'cipher': 'AES-256-GCM',
        'salt': base64Encode(salt),
        'nonce': base64Encode(encrypted.nonce),
        'mac': base64Encode(encrypted.mac.bytes),
        'ciphertext': base64Encode(encrypted.cipherText),
      });

      await expectLater(
        SecureBackupService.instance.restoreBackup(
          Uint8List.fromList(utf8.encode(envelope)),
          'different-backup-password',
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });

}
