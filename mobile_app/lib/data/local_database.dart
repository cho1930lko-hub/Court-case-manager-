import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../services/secure_database_key.dart';

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
    final key = await SecureDatabaseKey.instance.read() ??
        await SecureDatabaseKey.instance.create();
    await _migratePlainDatabaseIfNeeded(path, key);
    _db = await openDatabase(
      path,
      password: key,
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

  Future<void> _migratePlainDatabaseIfNeeded(String path, String key) async {
    final source = File(path);
    if (!await source.exists() || await source.length() == 0) return;
    final handle = await source.open();
    final header = await handle.read(16);
    await handle.close();
    const sqliteHeader = [83, 81, 76, 105, 116, 101, 32, 102, 111, 114, 109, 97, 116, 32, 51, 0];
    final isPlainSqlite = header.length == sqliteHeader.length &&
        List.generate(header.length, (i) => header[i] == sqliteHeader[i]).every((v) => v);
    if (!isPlainSqlite) return; // Encrypted database: SQLCipher will validate the stored key on open.

    final tempPath = '$path.sqlcipher_migrating';
    for (final suffix in ['', '-wal', '-shm']) {
      final stale = File('$tempPath$suffix');
      if (await stale.exists()) await stale.delete();
    }
    Database? plainDb;
    try {
      plainDb = await openDatabase(path);
      final versionRows = await plainDb.rawQuery('PRAGMA user_version');
      final legacyVersion = versionRows.isEmpty ? 0 : (versionRows.first.values.first as int? ?? 0);
      final escapedPath = tempPath.replaceAll("'", "''");
      final escapedKey = key.replaceAll("'", "''");
      await plainDb.execute("ATTACH DATABASE '$escapedPath' AS encrypted KEY '$escapedKey'");
      await plainDb.rawQuery("SELECT sqlcipher_export('encrypted')");
      await plainDb.execute('PRAGMA encrypted.user_version = $legacyVersion');
      await plainDb.execute('DETACH DATABASE encrypted');
      await plainDb.close();
      plainDb = null;
      for (final suffix in ['-wal', '-shm']) {
        final sidecar = File('$path$suffix');
        if (await sidecar.exists()) await sidecar.delete();
      }

      final migrated = File(tempPath);
      if (!await migrated.exists() || await migrated.length() < 100) {
        throw StateError('SQLCipher migration output is missing or incomplete.');
      }
      final verify = await openDatabase(tempPath, password: key, readOnly: true);
      try {
        final result = await verify.rawQuery('PRAGMA integrity_check');
        if (result.isEmpty || result.first.values.first != 'ok') {
          throw StateError('Encrypted database integrity check failed.');
        }
      } finally {
        await verify.close();
      }

      final backupPath = '$path.plaintext_migration_backup';
      if (await File(backupPath).exists()) await File(backupPath).delete();
      await source.rename(backupPath);
      try {
        await migrated.rename(path);
        await File(backupPath).delete();
      } catch (_) {
        if (await File(path).exists()) await File(path).delete();
        await File(backupPath).rename(path);
        rethrow;
      }
    } catch (_) {
      await plainDb?.close();
      rethrow; // Never delete or overwrite the original database on migration failure.
    } finally {
      final temp = File(tempPath);
      if (await temp.exists()) await temp.delete();
    }
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


  /// Aggregated preparation data for the upcoming-hearing workspace.
  /// Reads existing tables only; no schema or record migration is required.
  Future<List<Map<String, Object?>>> casePreparationSummary() async {
    final db = await database;
    return db.rawQuery('''
      SELECT c.*,
        COUNT(k.id) AS checklist_total,
        SUM(CASE WHEN k.status = 'पूर्ण' THEN 1 ELSE 0 END) AS checklist_done,
        SUM(CASE WHEN k.status != 'पूर्ण' THEN 1 ELSE 0 END) AS checklist_pending
      FROM cases c
      LEFT JOIN case_checklist k ON k.case_id = c.id
      WHERE c.is_archived = 0
      GROUP BY c.id
      ORDER BY
        CASE WHEN TRIM(COALESCE(c.next_hearing, '')) = '' THEN 1 ELSE 0 END,
        c.next_hearing ASC,
        CAST(c.st_no AS INTEGER) DESC
    ''');
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

  Future<List<Map<String, Object?>>> caseTimeline(String caseId) async {
    final db = await database;
    return db.query('case_timeline', where: 'case_id = ?', whereArgs: [caseId],
      orderBy: 'event_date DESC, created_at DESC');
  }

  Future<void> addTimelineEvent({
    required String id, required String caseId, required String date,
    required String type, required String description,
  }) async {
    final db = await database;
    await db.insert('case_timeline', {
      'id': id, 'case_id': caseId, 'event_date': date,
      'event_type': type, 'description': description,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, Object?>>> caseChecklist(String caseId) async {
    final db = await database;
    return db.query('case_checklist', where: 'case_id = ?', whereArgs: [caseId],
      orderBy: "CASE WHEN status = 'पूर्ण' THEN 1 ELSE 0 END, due_date ASC");
  }

  Future<void> addChecklistTask({
    required String id, required String caseId, required String task,
    required String dueDate, required String assignedTo, required String remarks,
  }) async {
    final db = await database;
    await db.insert('case_checklist', {
      'id': id, 'case_id': caseId, 'task_name': task,
      'status': 'लंबित', 'due_date': dueDate, 'assigned_to': assignedTo,
      'remarks': remarks, 'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> setChecklistStatus(String id, bool done) async {
    final db = await database;
    await db.update('case_checklist', {
      'status': done ? 'पूर्ण' : 'लंबित',
      'completed_date': done ? DateTime.now().toIso8601String() : '',
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, Object?>>> caseDocuments(String caseId) async {
    final db = await database;
    return db.query('case_documents', where: 'case_id = ?', whereArgs: [caseId],
      orderBy: 'created_at DESC');
  }

  Future<void> addCaseDocument({
    required String id, required String caseId, required String name,
    required String category, required String path, required String groupId,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.insert('case_documents', {
        'id': id, 'case_id': caseId, 'document_group_id': groupId,
        'name': name, 'category': category, 'local_path': path,
        'version': 1, 'remarks': '', 'created_at': now,
      });
      await txn.insert('document_versions', {
        'id': id, 'document_group_id': groupId, 'document_id': id,
        'version_number': 1, 'local_path': path,
        'change_remarks': 'मूल दस्तावेज़', 'created_at': now,
      });
    });
  }

  Future<List<Map<String, Object?>>> documentVersions(String documentId) async {
    final db = await database;
    final rows = await db.query(
      'document_versions', where: 'document_id = ?', whereArgs: [documentId],
      orderBy: 'version_number DESC, created_at DESC',
    );
    if (rows.isNotEmpty) return rows;
    final current = await db.query('case_documents', where: 'id = ?', whereArgs: [documentId], limit: 1);
    if (current.isEmpty) return [];
    final doc = current.first;
    return [{
      'id': 'legacy-${doc['id']}',
      'document_id': documentId,
      'version_number': doc['version'] ?? 1,
      'local_path': doc['local_path'] ?? '',
      'change_remarks': 'पहले से मौजूद वर्तमान संस्करण',
      'created_at': doc['created_at'] ?? '',
    }];
  }

  Future<void> addDocumentVersion({
    required String id, required String groupId, required String documentId,
    required int version, required String path, required String remarks,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final history = await txn.query(
        'document_versions', where: 'document_id = ?', whereArgs: [documentId], limit: 1,
      );
      if (history.isEmpty) {
        // Preserve the pre-existing file as version 1 for records created before history tracking.
        final current = await txn.query(
          'case_documents', where: 'id = ?', whereArgs: [documentId], limit: 1,
        );
        if (current.isNotEmpty) {
          final old = current.first;
          await txn.insert('document_versions', {
            'id': '${documentId}_legacy_v1',
            'document_group_id': groupId,
            'document_id': documentId,
            'version_number': old['version'] ?? 1,
            'local_path': old['local_path'] ?? '',
            'change_remarks': 'पहले से मौजूद मूल संस्करण',
            'created_at': old['created_at'] ?? now,
          });
        }
      }
      await txn.insert('document_versions', {
        'id': id, 'document_group_id': groupId, 'document_id': documentId,
        'version_number': version, 'local_path': path,
        'change_remarks': remarks, 'created_at': now,
      });
      await txn.update('case_documents', {
        'version': version, 'local_path': path, 'remarks': 'नवीनतम संस्करण',
      }, where: 'id = ?', whereArgs: [documentId]);
    });
  }

  Future<void> updateDocumentVersion(String id, int version, String path) async {
    final db = await database;
    await db.update('case_documents', {
      'version': version, 'local_path': path, 'remarks': 'नवीनतम संस्करण',
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, Object?>>> auditEntries({int limit = 300}) async {
    final db = await database;
    return db.query('audit_log', orderBy: 'created_at DESC', limit: limit);
  }

  Future<void> closeForRestore() async {
    await _db?.close();
    _db = null;
  }

  Future<String> databasePath() async {
    final root = await getDatabasesPath();
    return p.join(root, 'court_case_manager.db');
  }
}
