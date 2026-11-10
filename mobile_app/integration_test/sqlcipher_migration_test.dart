import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:court_case_manager/data/local_database.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'encrypted SQLCipher v4 database upgrades to v5 without losing legacy data',
    (tester) async {
      const password = 'phase8-sqlcipher-fixture-key-2026';
      final root = await getDatabasesPath();
      final path = p.join(root, 'phase8_sqlcipher_v4_fixture.db');

      // This is a disposable test fixture only; never point this test at the
      // application's production database filename.
      for (final suffix in ['', '-wal', '-shm']) {
        final file = await databaseExists('$path$suffix');
        if (file) await deleteDatabase('$path$suffix');
      }

      final legacy = await openDatabase(
        path,
        password: password,
        version: 4,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE cases (
              id TEXT PRIMARY KEY,
              st_no TEXT NOT NULL,
              accused_name TEXT NOT NULL DEFAULT ''
            )
          ''');
          await db.insert('cases', {
            'id': 'legacy-case-001',
            'st_no': '00027',
            'accused_name': 'पुराना सुरक्षित रिकॉर्ड',
          });

          await db.execute('''
            CREATE TABLE field_definitions (
              id TEXT PRIMARY KEY,
              module TEXT NOT NULL,
              field_key TEXT NOT NULL,
              label TEXT NOT NULL,
              data_type TEXT NOT NULL DEFAULT 'text',
              is_required INTEGER NOT NULL DEFAULT 0,
              is_active INTEGER NOT NULL DEFAULT 1,
              sort_order INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE custom_field_values (
              id TEXT PRIMARY KEY,
              module TEXT NOT NULL,
              record_id TEXT NOT NULL,
              field_id TEXT NOT NULL,
              value TEXT DEFAULT '',
              updated_at TEXT NOT NULL,
              UNIQUE(module, record_id, field_id)
            )
          ''');
          await db.execute('''
            CREATE TABLE field_values (
              id TEXT PRIMARY KEY,
              module TEXT NOT NULL,
              record_id TEXT NOT NULL,
              field_id TEXT NOT NULL,
              value TEXT NOT NULL DEFAULT '',
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              UNIQUE(module, record_id, field_id)
            )
          ''');
          await db.execute('''
            CREATE TABLE import_history (
              id TEXT PRIMARY KEY,
              module TEXT NOT NULL,
              source_name TEXT NOT NULL,
              total_rows INTEGER NOT NULL DEFAULT 0,
              imported_rows INTEGER NOT NULL DEFAULT 0,
              skipped_rows INTEGER NOT NULL DEFAULT 0,
              error_rows INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL
            )
          ''');
          await db.insert('field_definitions', {
            'id': 'field-old-1',
            'module': 'cases',
            'field_key': 'old_ref',
            'label': 'पुराना संदर्भ',
            'created_at': '2025-01-01',
            'updated_at': '2025-01-01',
          });
          await db.insert('field_values', {
            'id': 'field-value-old-1',
            'module': 'cases',
            'record_id': 'legacy-case-001',
            'field_id': 'field-old-1',
            'value': 'CUSTOM-0009',
            'created_at': '2025-01-01',
            'updated_at': '2025-01-02',
          });
          await db.insert('import_history', {
            'id': 'history-old-1',
            'module': 'cases',
            'source_name': 'legacy-export.xlsx',
            'total_rows': 12,
            'imported_rows': 10,
            'skipped_rows': 2,
            'error_rows': 0,
            'created_at': '2025-01-03',
          });

          await db.execute('CREATE TABLE migration_sentinel (value TEXT NOT NULL)');
          await db.insert('migration_sentinel', {'value': 'keep-me'});
          await db.execute(
            'CREATE INDEX idx_fixture_cases_st_no ON cases(st_no)',
          );
          await db.execute('''
            CREATE TABLE trigger_audit (case_id TEXT NOT NULL, seen_name TEXT NOT NULL)
          ''');
          await db.execute('''
            CREATE TRIGGER trg_fixture_case_update
            AFTER UPDATE OF accused_name ON cases
            BEGIN
              INSERT INTO trigger_audit(case_id, seen_name)
              VALUES (NEW.id, NEW.accused_name);
            END
          ''');
        },
      );
      expect(await legacy.rawQuery('PRAGMA integrity_check'), isNotEmpty);
      await legacy.close();

      final localDatabase = LocalDatabase.forTesting(
        await openDatabase(
          path,
          password: password,
          version: 5,
          onUpgrade: (db, oldVersion, newVersion) =>
              LocalDatabase.forTesting(db).migrateSchema(
            db,
            oldVersion,
            newVersion,
          ),
        ),
      );
      final upgraded = await localDatabase.database;
      // The injected handle is the already-upgraded encrypted database.
      final integrity = await upgraded.rawQuery('PRAGMA integrity_check');
      expect(integrity.first.values.first, 'ok');
      final version = await upgraded.rawQuery('PRAGMA user_version');
      expect(version.first.values.first, 5);

      final caseRows = await upgraded.query(
        'cases',
        where: 'id = ?',
        whereArgs: ['legacy-case-001'],
      );
      expect(caseRows.single['st_no'], '00027');
      expect(caseRows.single['accused_name'], 'पुराना सुरक्षित रिकॉर्ड');

      final copiedCustomValue = await upgraded.query(
        'custom_field_values',
        where: 'id = ?',
        whereArgs: ['field-value-old-1'],
      );
      expect(copiedCustomValue.single['value'], 'CUSTOM-0009');
      expect(await upgraded.query('field_values'), hasLength(1));

      final history = await upgraded.query(
        'import_history',
        where: 'id = ?',
        whereArgs: ['history-old-1'],
      );
      expect(history.single['source_name'], 'legacy-export.xlsx');
      expect(history.single['total_rows'], 12);
      expect(history.single['file_name'], '');

      final sentinel = await upgraded.query('migration_sentinel');
      expect(sentinel.single['value'], 'keep-me');

      final indexRows = await upgraded.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND name = ?",
        ['idx_fixture_cases_st_no'],
      );
      expect(indexRows, hasLength(1));
      final triggerRows = await upgraded.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name = ?",
        ['trg_fixture_case_update'],
      );
      expect(triggerRows, hasLength(1));

      await upgraded.update(
        'cases',
        {'accused_name': 'ट्रिगर जाँच'},
        where: 'id = ?',
        whereArgs: ['legacy-case-001'],
      );
      final triggerAudit = await upgraded.query('trigger_audit');
      expect(triggerAudit.single['seen_name'], 'ट्रिगर जाँच');

      await upgraded.close();
      await deleteDatabase(path);
    },
  );
}
