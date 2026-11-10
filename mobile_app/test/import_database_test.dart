import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:court_case_manager/data/local_database.dart';

void main() {
  late Database db;
  late LocalDatabase localDatabase;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute('''
      CREATE TABLE cases (
        id TEXT PRIMARY KEY,
        st_no TEXT NOT NULL UNIQUE,
        fir_no TEXT DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE field_definitions (
        id TEXT PRIMARY KEY,
        module TEXT NOT NULL,
        label TEXT NOT NULL DEFAULT '',
        is_active INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0
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
        UNIQUE(module, record_id, field_id),
        FOREIGN KEY(field_id) REFERENCES field_definitions(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE import_history (
        id TEXT PRIMARY KEY,
        module TEXT NOT NULL,
        file_name TEXT NOT NULL DEFAULT '',
        source_name TEXT NOT NULL DEFAULT '',
        total_rows INTEGER NOT NULL DEFAULT 0,
        imported_rows INTEGER NOT NULL DEFAULT 0,
        skipped_rows INTEGER NOT NULL DEFAULT 0,
        error_rows INTEGER NOT NULL DEFAULT 0,
        imported_at TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL DEFAULT '',
        details TEXT DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE import_row_errors (
        id TEXT PRIMARY KEY,
        import_id TEXT NOT NULL,
        module TEXT NOT NULL,
        source_name TEXT NOT NULL,
        source_row INTEGER NOT NULL,
        outcome TEXT NOT NULL,
        reason TEXT NOT NULL,
        row_data TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE audit_log (
        id TEXT PRIMARY KEY,
        action TEXT NOT NULL,
        module TEXT NOT NULL,
        record_id TEXT DEFAULT '',
        details TEXT DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');
    localDatabase = LocalDatabase.forTesting(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('duplicate rows are reported and existing records are never overwritten', () async {
    await db.insert('cases', {
      'id': 'existing',
      'st_no': '0012',
      'fir_no': 'OLD-FIR',
      'created_at': '2026-01-01',
      'updated_at': '2026-01-01',
    });

    final result = await localDatabase.importRegisterRows('cases', [
      {'st_no': '0012', 'fir_no': 'NEW-FIR'},
      {'st_no': '0013', 'fir_no': 'FIR-13'},
    ], sourceName: 'synthetic.xlsx / Session Court',
      sourceRowNumbers: [2, 3]);

    expect(result, {'total': 2, 'imported': 1, 'skipped': 1, 'errors': 0});
    final existing = await db.query('cases',
        where: 'st_no = ?', whereArgs: ['0012'], limit: 1);
    expect(existing.single['fir_no'], 'OLD-FIR');
    final added = await db.query('cases',
        where: 'st_no = ?', whereArgs: ['0013'], limit: 1);
    expect(added, hasLength(1));
    final issues = await db.query('import_row_errors');
    expect(issues.single['outcome'], 'duplicate');
    expect(issues.single['source_row'], 2);
  });

  test('custom-field failure rolls back the register row and is recorded', () async {
    final result = await localDatabase.importRegisterRows('cases', [
      {
        'st_no': '0020',
        'fir_no': 'FIR-20',
        'custom:missing-field-definition': 'must not partially persist',
      },
    ], sourceName: 'synthetic.xlsx / Session Court',
      sourceRowNumbers: [7]);

    expect(result, {'total': 1, 'imported': 0, 'skipped': 0, 'errors': 1});
    expect(await db.query('cases'), isEmpty);
    final issues = await db.query('import_row_errors');
    expect(issues, hasLength(1));
    expect(issues.single['outcome'], 'error');
    expect(issues.single['source_row'], 7);
  });

  test('preview-rejected rows remain in the row-level report', () async {
    final result = await localDatabase.importRegisterRows('cases', [],
      sourceName: 'synthetic.xlsx / Session Court',
      preRejectedRows: [
        {
          'source_row': 9,
          'reason': 'ST No. आवश्यक है',
          'row_data': {'ST NO': '', 'बनाम': 'उदाहरण'},
        },
      ]);

    expect(result, {'total': 1, 'imported': 0, 'skipped': 1, 'errors': 0});
    final issues = await db.query('import_row_errors');
    expect(issues.single['outcome'], 'invalid');
    expect(issues.single['source_row'], 9);
  });
}
