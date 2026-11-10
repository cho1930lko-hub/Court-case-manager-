import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:court_case_manager/data/local_database.dart';

void main() {
  late Database db;
  late LocalDatabase localDatabase;

  setUpAll(() => sqfliteFfiInit());

  Future<void> createLegacyV4Schema({
    required bool includeLegacyFieldValues,
    required bool historyUsesSourceName,
  }) async {
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
    if (includeLegacyFieldValues) {
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
    }
    if (historyUsesSourceName) {
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
    } else {
      await db.execute('''
        CREATE TABLE import_history (
          id TEXT PRIMARY KEY,
          module TEXT NOT NULL,
          file_name TEXT NOT NULL,
          total_rows INTEGER NOT NULL DEFAULT 0,
          imported_rows INTEGER NOT NULL DEFAULT 0,
          skipped_rows INTEGER NOT NULL DEFAULT 0,
          error_rows INTEGER NOT NULL DEFAULT 0,
          imported_at TEXT NOT NULL,
          details TEXT DEFAULT ''
        )
      ''');
    }
  }

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    localDatabase = LocalDatabase.forTesting(db);
  });

  tearDown(() async => db.close());

  test('v4 source_name schema upgrades additively and retains legacy values', () async {
    await createLegacyV4Schema(
      includeLegacyFieldValues: true,
      historyUsesSourceName: true,
    );
    await db.insert('field_definitions', {
      'id': 'field-court-ref',
      'module': 'cases',
      'field_key': 'court_ref',
      'label': 'Court Reference',
      'created_at': '2025-01-01',
      'updated_at': '2025-01-01',
    });
    await db.insert('field_values', {
      'id': 'legacy-value-1',
      'module': 'cases',
      'record_id': 'case-1',
      'field_id': 'field-court-ref',
      'value': 'पुराना मान',
      'created_at': '2025-01-01',
      'updated_at': '2025-01-02',
    });
    await db.insert('import_history', {
      'id': 'history-1',
      'module': 'cases',
      'source_name': 'old-sheet',
      'total_rows': 10,
      'imported_rows': 8,
      'skipped_rows': 2,
      'error_rows': 0,
      'created_at': '2025-01-03',
    });

    await localDatabase.migrateSchema(db, 4, 5);

    final definition = (await db.query('field_definitions')).single;
    expect(definition['label'], 'Court Reference');
    expect(definition['is_system'], 0);
    expect(definition['allowed_roles'], 'admin,staff');
    expect(definition['is_dropdown'], 0);

    final copied = await db.query('custom_field_values',
      where: 'id = ?', whereArgs: ['legacy-value-1']);
    expect(copied.single['value'], 'पुराना मान');
    expect(await db.query('field_values'), hasLength(1));

    final history = (await db.query('import_history')).single;
    expect(history['source_name'], 'old-sheet');
    expect(history['file_name'], '');
    expect(history['created_at'], '2025-01-03');
    expect(history['imported_at'], '');
    expect(await db.query('import_row_errors'), isEmpty);
  });

  test('v4 file_name schema upgrades without dropping existing import history', () async {
    await createLegacyV4Schema(
      includeLegacyFieldValues: false,
      historyUsesSourceName: false,
    );
    await db.insert('import_history', {
      'id': 'history-2',
      'module': 'dak_register',
      'file_name': 'legacy.xlsx',
      'total_rows': 4,
      'imported_rows': 3,
      'skipped_rows': 1,
      'error_rows': 0,
      'imported_at': '2025-02-03',
      'details': 'legacy import details',
    });

    await localDatabase.migrateSchema(db, 4, 5);

    final history = (await db.query('import_history')).single;
    expect(history['file_name'], 'legacy.xlsx');
    expect(history['imported_at'], '2025-02-03');
    expect(history['details'], 'legacy import details');
    expect(history['source_name'], '');
    expect(history['created_at'], '');
    expect(await db.query('import_row_errors'), isEmpty);
  });

  test('schema repair is safe to run a second time', () async {
    await createLegacyV4Schema(
      includeLegacyFieldValues: false,
      historyUsesSourceName: true,
    );

    await localDatabase.migrateSchema(db, 4, 5);
    await localDatabase.migrateSchema(db, 4, 5);

    final columns = await db.rawQuery('PRAGMA table_info(import_history)');
    expect(columns.map((row) => row['name']), containsAll([
      'file_name', 'source_name', 'imported_at', 'created_at', 'details',
    ]));
    expect(await db.query('import_row_errors'), isEmpty);
  });
}
