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
}
