import 'package:flutter_test/flutter_test.dart';
import 'package:court_case_manager/services/app_lock_service.dart';
import 'package:court_case_manager/services/secure_backup_service.dart';

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

  group('SecureBackupService password validation', () {
    test('rejects password shorter than twelve characters before file access', () async {
      await expectLater(
        SecureBackupService.instance.createBackup('short-pass'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
