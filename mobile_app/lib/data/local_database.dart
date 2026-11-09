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
      version: 2,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.execute('PRAGMA journal_mode = WAL');
      },
      onCreate: _createSchema,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createGeneratedDocumentsTable(db);
      },
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
    await _createGeneratedDocumentsTable(db);
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

  Future<void> _createGeneratedDocumentsTable(Database db) async {
    await db.execute('''
      CREATE TABLE generated_documents (
        id TEXT PRIMARY KEY, case_id TEXT NOT NULL, document_type TEXT NOT NULL,
        content TEXT NOT NULL, created_at TEXT NOT NULL,
        FOREIGN KEY(case_id) REFERENCES cases(id)
      )
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
      'contacts': await count('address_book'),
    };
  }


  Future<List<Map<String, Object?>>> searchCases(String query) async {
    final db = await database;
    final q = query.trim();
    if (q.isEmpty) {
      return db.query('cases', where: 'is_archived = 0', orderBy: 'CAST(st_no AS INTEGER) DESC');
    }
    return db.query(
      'cases',
      where: 'is_archived = 0 AND (st_no LIKE ? OR fir_no LIKE ? OR accused_name LIKE ? OR sections LIKE ?)',
      whereArgs: ['%$q%', '%$q%', '%$q%', '%$q%'],
      orderBy: 'updated_at DESC',
    );
  }

  Future<void> saveCase(Map<String, Object?> values, {String? id}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    if (id == null) {
      await db.insert('cases', {
        ...values,
        'id': values['id'],
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    } else {
      await db.update('cases', {...values, 'updated_at': now},
          where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<void> archiveCase(String id) async {
    final db = await database;
    await db.update('cases', {
      'is_archived': 1,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> logAction(String action, String module, String recordId, String details) async {
    final db = await database;
    await db.insert('audit_log', {
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'action': action,
      'module': module,
      'record_id': recordId,
      'details': details,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, Object?>>> searchRegister(String table, String query) async {
    const allowed = {'dak_register', 'remand_register', 'address_book'};
    if (!allowed.contains(table)) throw ArgumentError('Unsupported register: $table');
    final db = await database;
    final q = query.trim();
    if (q.isEmpty) {
      return db.query(table, orderBy: 'created_at DESC');
    }
    final columns = switch (table) {
      'dak_register' => ['st_no', 'accused_name', 'dak_type', 'court_name', 'related_station', 'remarks'],
      'remand_register' => ['fir_no', 'sections', 'court_name', 'investigating_officer', 'accused_details'],
      _ => ['name', 'mobile', 'department', 'address'],
    };
    final where = columns.map((column) => '$column LIKE ?').join(' OR ');
    return db.query(table, where: where, whereArgs: List.filled(columns.length, '%$q%'),
        orderBy: 'created_at DESC');
  }

  Future<void> saveRegister(String table, Map<String, Object?> values,
      {required String id, required bool isNew}) async {
    const allowed = {'dak_register', 'remand_register', 'address_book'};
    if (!allowed.contains(table)) throw ArgumentError('Unsupported register: $table');
    final db = await database;
    final now = DateTime.now().toIso8601String();
    if (isNew) {
      await db.insert(table, {
        ...values,
        'id': id,
        'created_at': now,
        if (table != 'remand_register') 'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    } else {
      await db.update(table, {
        ...values,
        if (table != 'remand_register') 'updated_at': now,
      }, where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<void> saveGeneratedDocument({
    required String id,
    required String caseId,
    required String type,
    required String content,
  }) async {
    final db = await database;
    await db.insert('generated_documents', {
      'id': id,
      'case_id': caseId,
      'document_type': type,
      'content': content,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<String> databasePath() async {
    final root = await getDatabasesPath();
    return p.join(root, 'court_case_manager.db');
  }
}
