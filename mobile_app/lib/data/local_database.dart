import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local-first database. No network or Google account is required.
/// Schema is additive: future upgrades must use versioned migrations.
class LocalDatabase {
  LocalDatabase._();
  static final LocalDatabase instance = LocalDatabase._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final root = await getDatabasesPath();
    final path = p.join(root, 'court_case_manager.db');
    _db = await openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.execute('PRAGMA journal_mode = WAL');
      },
      onCreate: _createSchema,
    );
    return _db!;
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE cases (
        id TEXT PRIMARY KEY,
        st_no TEXT NOT NULL UNIQUE,
        fir_no TEXT DEFAULT '',
        sections TEXT DEFAULT '',
        accused_name TEXT DEFAULT '',
        court_name TEXT DEFAULT '',
        summoned_witnesses TEXT DEFAULT '',
        previous_hearing TEXT DEFAULT '',
        next_hearing TEXT DEFAULT '',
        status TEXT DEFAULT '',
        summons_status TEXT DEFAULT '',
        monitoring_type TEXT DEFAULT '',
        action_taken TEXT DEFAULT '',
        total_witnesses INTEGER DEFAULT 0,
        fir_date TEXT DEFAULT '',
        charge_sheet_date TEXT DEFAULT '',
        cognizance_date TEXT DEFAULT '',
        charge_framed_date TEXT DEFAULT '',
        station_received_date TEXT DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_archived INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX idx_cases_next_hearing ON cases(next_hearing)');
    await db.execute('CREATE INDEX idx_cases_status ON cases(status)');

    await db.execute('''
      CREATE TABLE dak_register (
        id TEXT PRIMARY KEY, st_no TEXT DEFAULT '', accused_name TEXT DEFAULT '',
        status TEXT DEFAULT '', dak_type TEXT DEFAULT '', person_address TEXT DEFAULT '',
        related_station TEXT DEFAULT '', court_name TEXT DEFAULT '',
        station_received_date TEXT DEFAULT '', hearing_date TEXT DEFAULT '',
        remarks TEXT DEFAULT '', attachment_path TEXT DEFAULT '',
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE remand_register (
        id TEXT PRIMARY KEY, remand_date TEXT DEFAULT '', fir_no TEXT DEFAULT '',
        sections TEXT DEFAULT '', court_name TEXT DEFAULT '', investigating_officer TEXT DEFAULT '',
        first_remand_date TEXT DEFAULT '', accused_details TEXT DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE address_book (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, address TEXT DEFAULT '',
        mobile TEXT DEFAULT '', department TEXT DEFAULT '', created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE case_documents (
        id TEXT PRIMARY KEY, case_id TEXT NOT NULL, document_group_id TEXT NOT NULL,
        name TEXT NOT NULL, category TEXT DEFAULT '', local_path TEXT NOT NULL,
        version INTEGER NOT NULL DEFAULT 1, remarks TEXT DEFAULT '',
        created_at TEXT NOT NULL, FOREIGN KEY(case_id) REFERENCES cases(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE case_timeline (
        id TEXT PRIMARY KEY, case_id TEXT NOT NULL, event_date TEXT NOT NULL,
        event_type TEXT NOT NULL, description TEXT NOT NULL, document_id TEXT DEFAULT '',
        created_at TEXT NOT NULL, FOREIGN KEY(case_id) REFERENCES cases(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE case_checklist (
        id TEXT PRIMARY KEY, case_id TEXT NOT NULL, task_name TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'लंबित', due_date TEXT DEFAULT '',
        completed_date TEXT DEFAULT '', assigned_to TEXT DEFAULT '',
        remarks TEXT DEFAULT '', updated_at TEXT NOT NULL,
        FOREIGN KEY(case_id) REFERENCES cases(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE document_analysis (
        id TEXT PRIMARY KEY, case_id TEXT NOT NULL, document_id TEXT DEFAULT '',
        extracted_text TEXT DEFAULT '', summary TEXT DEFAULT '',
        review_status TEXT NOT NULL DEFAULT 'मानवीय समीक्षा लंबित',
        created_at TEXT NOT NULL, FOREIGN KEY(case_id) REFERENCES cases(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE ai_drafts (
        id TEXT PRIMARY KEY, case_id TEXT NOT NULL, draft_type TEXT NOT NULL,
        facts TEXT DEFAULT '', draft_text TEXT DEFAULT '',
        status TEXT NOT NULL DEFAULT 'मानवीय समीक्षा लंबित',
        created_at TEXT NOT NULL, FOREIGN KEY(case_id) REFERENCES cases(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE document_versions (
        id TEXT PRIMARY KEY, document_group_id TEXT NOT NULL,
        document_id TEXT NOT NULL, version_number INTEGER NOT NULL,
        local_path TEXT NOT NULL, change_remarks TEXT DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE audit_log (
        id TEXT PRIMARY KEY, action TEXT NOT NULL, module TEXT NOT NULL,
        record_id TEXT DEFAULT '', details TEXT DEFAULT '', created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY, value TEXT NOT NULL
      )
    ''');
    await db.execute('''
      INSERT INTO app_settings(key, value) VALUES
      ('schema_label', 'offline_v1'),
      ('data_owner', 'this_device')
    ''');
  }

  Future<Map<String, int>> dashboardCounts() async {
    final db = await database;
    Future<int> count(String table) async =>
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $table')) ?? 0;
    return {
      'cases': await count('cases'),
      'dak': await count('dak_register'),
      'remand': await count('remand_register'),
      'documents': await count('case_documents'),
    };
  }

  Future<String> databasePath() async {
    final root = await getDatabasesPath();
    return p.join(root, 'court_case_manager.db');
  }
}
