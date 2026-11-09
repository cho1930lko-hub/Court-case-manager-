import 'package:flutter_test/flutter_test.dart';
import 'package:court_case_manager/services/app_lock_service.dart';
import 'package:court_case_manager/services/secure_backup_service.dart';
import 'package:court_case_manager/services/backup_path_validator.dart';

void main() {
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
    test('accepts files under case_documents', () {
      expect(safeCaseDocumentRelativePath('case_documents/case-1/order.pdf'),
          'case-1/order.pdf');
    });

    test('rejects parent traversal that normalizes outside the document root', () {
      expect(
        () => safeCaseDocumentRelativePath('case_documents/../outside.txt'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects nested traversal and absolute paths', () {
      expect(
        () => safeCaseDocumentRelativePath(r'case_documents/a\\..\\..\\outside.txt'),
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
