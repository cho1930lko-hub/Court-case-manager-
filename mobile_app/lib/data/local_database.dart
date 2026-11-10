import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../services/secure_database_key.dart';

/// Local-first database. No network or Google account is required.
/// Schema is additive: future upgrades must use versioned migrations.
class LocalDatabase {
  LocalDatabase._();

  /// Injects an already-open sqflite-compatible database for deterministic tests.
  LocalDatabase.forTesting(Database database) : _db = database;

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
      version: 5,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        // journal_mode returns a result row; use rawQuery rather than execute.
        await db.rawQuery('PRAGMA journal_mode = WAL');
      },
      onCreate: _createSchema,
      onUpgrade: migrateSchema,
    );
    return _db!;
  }

  /// Shared upgrade dispatcher used by sqflite and migration tests.
  /// Keep every version step additive so existing records remain intact.
  Future<void> migrateSchema(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) await _createGeneratedDocumentsTable(db);
    if (oldVersion < 3) await _createEvidenceTable(db);
    if (oldVersion < 4) await _createDynamicFieldTables(db);
    if (oldVersion < 4) await _createDynamicDataTables(db);
    if (oldVersion < 5) await ensurePhase8MigrationSchema(db);
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
    await _createEvidenceTable(db);
    await _createDynamicFieldTables(db);
    await _createDynamicDataTables(db);
    await ensurePhase8MigrationSchema(db);
  }

  Future<void> _createDynamicDataTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS field_definitions (
      id TEXT PRIMARY KEY, module TEXT NOT NULL, field_key TEXT NOT NULL,
      label TEXT NOT NULL, data_type TEXT NOT NULL DEFAULT 'text',
      is_required INTEGER NOT NULL DEFAULT 0, is_dropdown INTEGER NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1, sort_order INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
      UNIQUE(module, field_key)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS field_options (
      id TEXT PRIMARY KEY, field_id TEXT NOT NULL, option_label TEXT NOT NULL,
      sort_order INTEGER NOT NULL DEFAULT 0, is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      FOREIGN KEY(field_id) REFERENCES field_definitions(id) ON DELETE CASCADE
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS field_values (
      id TEXT PRIMARY KEY, module TEXT NOT NULL, record_id TEXT NOT NULL,
      field_id TEXT NOT NULL, value TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL, UNIQUE(module, record_id, field_id),
      FOREIGN KEY(field_id) REFERENCES field_definitions(id)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS field_permissions (
      id TEXT PRIMARY KEY, module TEXT NOT NULL, field_id TEXT NOT NULL,
      role TEXT NOT NULL, can_view INTEGER NOT NULL DEFAULT 1,
      can_edit INTEGER NOT NULL DEFAULT 0, UNIQUE(module, field_id, role),
      FOREIGN KEY(field_id) REFERENCES field_definitions(id) ON DELETE CASCADE
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS import_history (
      id TEXT PRIMARY KEY, module TEXT NOT NULL, file_name TEXT NOT NULL,
      total_rows INTEGER NOT NULL DEFAULT 0, imported_rows INTEGER NOT NULL DEFAULT 0,
      skipped_rows INTEGER NOT NULL DEFAULT 0, error_rows INTEGER NOT NULL DEFAULT 0,
      imported_at TEXT NOT NULL, details TEXT DEFAULT ''
    )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_field_values_record ON field_values(module, record_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_field_definitions_module ON field_definitions(module, is_active)');
  }

  /// Additive schema repair for the overlapping v4 dynamic-field table creators.
  /// Existing field definitions and values are retained; only missing columns are added.
  Future<void> ensurePhase8MigrationSchema(DatabaseExecutor db) async {
    Future<Set<String>> columns(String table) async {
      final rows = await db.rawQuery('PRAGMA table_info($table)');
      return rows.map((row) => row['name'].toString()).toSet();
    }

    Future<void> addMissing(String table, Map<String, String> definitions) async {
      final existing = await columns(table);
      for (final entry in definitions.entries) {
        if (!existing.contains(entry.key)) {
          await db.execute('ALTER TABLE $table ADD COLUMN ${entry.key} ${entry.value}');
        }
      }
    }

    await addMissing('field_definitions', {
      'is_system': 'INTEGER NOT NULL DEFAULT 0',
      'allowed_roles': "TEXT NOT NULL DEFAULT 'admin,staff'",
      'is_dropdown': 'INTEGER NOT NULL DEFAULT 0',
    });
    await addMissing('import_history', {
      'file_name': "TEXT NOT NULL DEFAULT ''",
      'source_name': "TEXT NOT NULL DEFAULT ''",
      'imported_at': "TEXT NOT NULL DEFAULT ''",
      'created_at': "TEXT NOT NULL DEFAULT ''",
      'details': "TEXT NOT NULL DEFAULT ''",
    });
    await db.execute('''
      CREATE TABLE IF NOT EXISTS import_row_errors (
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
    await db.execute('CREATE INDEX IF NOT EXISTS idx_import_row_errors_import ON import_row_errors(import_id, source_row)');

    // v4 created both value tables with overlapping purposes. Copy any legacy
    // field_values rows into the table used by the app; keep the source table intact.
    final legacyValueTable = await columns('field_values');
    if (legacyValueTable.containsAll({
      'id', 'module', 'record_id', 'field_id', 'value', 'updated_at',
    })) {
      await db.execute('''
        INSERT OR IGNORE INTO custom_field_values
          (id, module, record_id, field_id, value, updated_at)
        SELECT id, module, record_id, field_id, value, updated_at
        FROM field_values
      ''');
    }
  }

  Future<List<Map<String, Object?>>> latestImportRowErrors(
      String module, String sourceName) async {
    final db = await database;
    final history = await db.query('import_history',
      columns: ['id'], where: 'module = ? AND source_name = ?',
      whereArgs: [module, sourceName], orderBy: 'created_at DESC, imported_at DESC',
      limit: 1);
    if (history.isEmpty) return [];
    return db.query('import_row_errors',
      where: 'import_id = ?', whereArgs: [history.first['id']],
      orderBy: 'source_row ASC');
  }

  Future<void> _createEvidenceTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS evidence_items (
        id TEXT PRIMARY KEY,
        case_id TEXT NOT NULL,
        item_type TEXT NOT NULL DEFAULT 'अन्य',
        description TEXT NOT NULL,
        seizure_date TEXT DEFAULT '',
        seized_from TEXT DEFAULT '',
        malkhana_entry TEXT DEFAULT '',
        seal_details TEXT DEFAULT '',
        exhibit_no TEXT DEFAULT '',
        produced_in_court INTEGER NOT NULL DEFAULT 0,
        local_path TEXT DEFAULT '',
        remarks TEXT DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(case_id) REFERENCES cases(id)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_evidence_case ON evidence_items(case_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_evidence_exhibit ON evidence_items(exhibit_no)');
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


  /// Additive metadata layer for user-configurable fields and dropdowns.
  /// Existing register columns and records remain untouched.
  Future<void> _createDynamicFieldTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS field_definitions (
        id TEXT PRIMARY KEY,
        module TEXT NOT NULL,
        field_key TEXT NOT NULL,
        label TEXT NOT NULL,
        data_type TEXT NOT NULL DEFAULT 'text',
        is_required INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        is_system INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        allowed_roles TEXT NOT NULL DEFAULT 'admin,staff',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(module, field_key)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS field_options (
        id TEXT PRIMARY KEY,
        field_id TEXT NOT NULL,
        option_label TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        FOREIGN KEY(field_id) REFERENCES field_definitions(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS custom_field_values (
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
      CREATE TABLE IF NOT EXISTS import_profiles (
        id TEXT PRIMARY KEY,
        module TEXT NOT NULL,
        profile_name TEXT NOT NULL,
        mapping_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS import_history (
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
    await db.execute('CREATE INDEX IF NOT EXISTS idx_custom_values_record ON custom_field_values(module, record_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_field_definitions_module ON field_definitions(module, is_active, sort_order)');
  }

  Future<List<Map<String, Object?>>> getFieldDefinitions(String module) async {
    final db = await database;
    return db.query('field_definitions', where: 'module = ? AND is_active = 1',
        whereArgs: [module], orderBy: 'sort_order, label');
  }

  Future<List<Map<String, Object?>>> getFieldOptions(String fieldId) async {
    final db = await database;
    return db.query('field_options', where: 'field_id = ? AND is_active = 1',
        whereArgs: [fieldId], orderBy: 'sort_order, option_label');
  }

  Future<void> saveFieldDefinition({
    required String id, required String module, required String fieldKey,
    required String label, required String dataType, required bool requiredField,
    required String allowedRoles, bool isSystem = false,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.insert('field_definitions', {
      'id': id, 'module': module, 'field_key': fieldKey, 'label': label,
      'data_type': dataType, 'is_required': requiredField ? 1 : 0,
      'allowed_roles': allowedRoles, 'is_system': isSystem ? 1 : 0,
      'created_at': now, 'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
    await logAction('FIELD_DEFINITION_CREATED', 'FIELD_MANAGER', id, '$module / $label');
  }

  Future<void> updateFieldDefinition(String id, {
    required String label, required String dataType,
    required bool requiredField, required String allowedRoles,
  }) async {
    final db = await database;
    final changed = await db.update('field_definitions', {
      'label': label, 'data_type': dataType,
      'is_required': requiredField ? 1 : 0,
      'allowed_roles': allowedRoles,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ? AND is_system = 0', whereArgs: [id]);
    if (changed != 1) throw StateError('System field cannot be modified or field not found');
    await logAction('FIELD_DEFINITION_UPDATED', 'FIELD_MANAGER', id, label);
  }

  Future<void> addFieldOption(String id, String fieldId, String label) async {
    final db = await database;
    await db.insert('field_options', {
      'id': id, 'field_id': fieldId, 'option_label': label,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.abort);
    await logAction('FIELD_OPTION_ADDED', 'FIELD_MANAGER', id, label);
  }

  Future<void> deactivateFieldDefinition(String id) async {
    final db = await database;
    final changed = await db.update('field_definitions', {
      'is_active': 0, 'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ? AND is_system = 0', whereArgs: [id]);
    if (changed != 1) throw StateError('System field cannot be deactivated or field not found');
    await logAction('FIELD_DEFINITION_DEACTIVATED', 'FIELD_MANAGER', id, 'Soft disable');
  }

  Future<void> saveCustomFieldValues(String module, String recordId,
      Map<String, String> values) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      for (final entry in values.entries) {
        await txn.insert('custom_field_values', {
          'id': '${module}_${recordId}_${entry.key}',
          'module': module, 'record_id': recordId,
          'field_id': entry.key, 'value': entry.value, 'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await _insertAudit(txn, 'CUSTOM_FIELDS_SAVED', module, recordId,
          '${values.length} custom field(s)');
    });
  }

  Future<Map<String, String>> getCustomFieldValues(String module, String recordId) async {
    final db = await database;
    final rows = await db.query('custom_field_values',
        where: 'module = ? AND record_id = ?', whereArgs: [module, recordId]);
    return {for (final row in rows) row['field_id'].toString(): (row['value'] ?? '').toString()};
  }


  Future<List<String>> importableColumns(String table) async {
    const allowed = {'cases', 'dak_register', 'remand_register', 'address_book'};
    if (!allowed.contains(table)) throw ArgumentError('Unsupported import table');
    final db = await database;
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    final columns = rows.map((row) => row['name'].toString())
      .where((name) => !{'id', 'created_at', 'updated_at', 'is_archived'}.contains(name))
      .toList();
    final custom = await db.query('field_definitions', columns: ['id'],
      where: 'module = ? AND is_active = 1', whereArgs: [table], orderBy: 'sort_order, label');
    columns.addAll(custom.map((field) => 'custom:${field['id']}'));
    return columns;
  }

  Future<List<Map<String, Object?>>> exportRegisterRows(String table) async {
    const allowed = {'cases', 'dak_register', 'remand_register', 'address_book'};
    if (!allowed.contains(table)) throw ArgumentError('Unsupported export table');
    final db = await database;
    final rows = await db.query(table, orderBy: 'created_at DESC');
    final fields = await db.query('field_definitions', columns: ['id', 'label'],
      where: 'module = ? AND is_active = 1', whereArgs: [table], orderBy: 'sort_order, label');
    for (final row in rows) {
      final values = await db.query('custom_field_values',
        where: 'module = ? AND record_id = ?', whereArgs: [table, row['id']]);
      for (final field in fields) {
        final value = values.where((v) => v['field_id'] == field['id']).toList();
        row[field['label'].toString()] = value.isEmpty ? '' : (value.first['value'] ?? '');
      }
    }
    return rows;
  }

  /// Imports rows atomically. Existing records are never overwritten.
  /// Imports selected rows without overwriting existing records.
  /// Every skipped or failed source row is retained in import_row_errors for review.
  Future<Map<String, int>> importRegisterRows(String table,
      List<Map<String, Object?>> rows, {
        required String sourceName,
        List<int>? sourceRowNumbers,
        List<Map<String, Object?>> preRejectedRows = const [],
      }) async {
    const allowed = {'cases', 'dak_register', 'remand_register', 'address_book'};
    if (!allowed.contains(table)) throw ArgumentError('Unsupported import table');
    if (sourceRowNumbers != null && sourceRowNumbers.length != rows.length) {
      throw ArgumentError('sourceRowNumbers length must match rows length');
    }
    final db = await database;
    final columns = await importableColumns(table);
    final now = DateTime.now().toIso8601String();
    final importId = '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    var imported = 0, skipped = 0, errors = 0;

    await db.transaction((txn) async {
      Future<void> recordIssueAt(int sourceRow, String outcome, String reason,
          Map<String, Object?> source) async {
        await txn.insert('import_row_errors', {
          'id': '${importId}_$sourceRow',
          'import_id': importId,
          'module': table,
          'source_name': sourceName,
          'source_row': sourceRow,
          'outcome': outcome,
          'reason': reason,
          'row_data': jsonEncode(source),
          'created_at': now,
        });
      }

      Future<void> recordIssue(int index, String outcome, String reason,
          Map<String, Object?> source) async {
        final sourceRow = sourceRowNumbers == null ? index + 2 : sourceRowNumbers[index];
        await recordIssueAt(sourceRow, outcome, reason, source);
      }

      for (final rejected in preRejectedRows) {
        final sourceRow = (rejected['source_row'] as num?)?.toInt();
        final reason = (rejected['reason'] ?? 'पंक्ति मान्य नहीं है').toString();
        final rowData = rejected['row_data'];
        if (sourceRow == null) {
          throw ArgumentError('preRejectedRows requires a numeric source_row');
        }
        skipped++;
        await recordIssueAt(sourceRow, 'invalid', reason,
          rowData is Map<String, Object?> ? rowData : <String, Object?>{});
      }

      for (var index = 0; index < rows.length; index++) {
        final source = rows[index];
        final values = <String, Object?>{};
        final customValues = <String, String>{};
        for (final entry in source.entries) {
          if (entry.key.startsWith('custom:')) {
            final fieldId = entry.key.substring(7);
            if (entry.value != null && entry.value.toString().trim().isNotEmpty) {
              customValues[fieldId] = entry.value.toString().trim();
            }
          } else if (columns.contains(entry.key) && entry.value != null) {
            values[entry.key] = entry.value;
          }
        }

        if (values.values.every((v) => v.toString().trim().isEmpty) && customValues.isEmpty) {
          skipped++;
          await recordIssue(index, 'skipped', 'रिकॉर्ड में कोई mapped value नहीं है', source);
          continue;
        }

        try {
          final id = (values.remove('id') ??
              '${DateTime.now().microsecondsSinceEpoch}-$index').toString();

          final hasStNo = (values['st_no']?.toString().trim().isNotEmpty ?? false);
          final hasFir = (values['fir_no']?.toString().trim().isNotEmpty ?? false);
          final hasRemandDate = (values['remand_date']?.toString().trim().isNotEmpty ?? false);
          final hasDakType = (values['dak_type']?.toString().trim().isNotEmpty ?? false);
          final hasMobile = (values['mobile']?.toString().trim().isNotEmpty ?? false);
          final keyComplete = switch (table) {
            'cases' => hasStNo,
            'dak_register' => hasStNo && hasDakType,
            'remand_register' => hasFir && hasRemandDate,
            'address_book' => hasMobile,
            _ => false,
          };
          if (!keyComplete) {
            skipped++;
            await recordIssue(index, 'needs_review',
              'डुप्लीकेट जाँच की पहचान कुंजी अधूरी है; मैनुअल समीक्षा आवश्यक', source);
            continue;
          }

          final duplicate = switch (table) {
            'cases' => (values['st_no']?.toString().trim().isNotEmpty ?? false)
              ? await txn.query(table, columns: ['id'], where: 'st_no = ?',
                  whereArgs: [values['st_no'].toString()], limit: 1)
              : <Map<String, Object?>>[],
            'address_book' => await txn.query(table, columns: ['id', 'name'],
              where: 'mobile = ?', whereArgs: [values['mobile'].toString()], limit: 10),
            'remand_register' =>
              (values['fir_no']?.toString().trim().isNotEmpty ?? false) &&
              (values['remand_date']?.toString().trim().isNotEmpty ?? false)
              ? await txn.query(table, columns: ['id'],
                  where: 'fir_no = ? AND remand_date = ?',
                  whereArgs: [values['fir_no'].toString(), values['remand_date'].toString()],
                  limit: 1)
              : <Map<String, Object?>>[],
            _ => await txn.query(table, columns: ['id', 'dak_type'],
              where: 'st_no = ?', whereArgs: [values['st_no'].toString()], limit: 10),
          };
          if (duplicate.isNotEmpty) {
            final isDakPossibleMatch = table == 'dak_register' &&
              duplicate.every((row) => (row['dak_type'] ?? '').toString().trim().toLowerCase() !=
                values['dak_type'].toString().trim().toLowerCase());
            final isSharedMobile = table == 'address_book' &&
              duplicate.any((row) => (row['name'] ?? '').toString().trim().toLowerCase() !=
                values['name'].toString().trim().toLowerCase());
            final needsReview = isDakPossibleMatch || isSharedMobile;
            skipped++;
            await recordIssue(index, needsReview ? 'needs_review' : 'duplicate',
              isDakPossibleMatch
                ? 'समान STN पर अलग Type वाला रिकॉर्ड मिला; मैनुअल समीक्षा आवश्यक'
                : isSharedMobile
                  ? 'समान मोबाइल नंबर अलग नाम से मिला; साझा नंबर की मैनुअल समीक्षा आवश्यक'
                  : 'पहचान कुंजी से मिलता-जुलता रिकॉर्ड पहले से मौजूद है', source);
            continue;
          }

          // Treat one source row as an atomic unit. If a custom-field write fails
          // after the register row was inserted, roll the whole row back so the
          // exception report can never disagree with a partially persisted record.
          final savepoint = 'import_row_$index';
          await txn.execute('SAVEPOINT $savepoint');
          try {
            // Null identity fields are not proof of uniqueness. Let the table's
            // NOT NULL / UNIQUE constraints reject invalid rows and capture the reason.
            await txn.insert(table, {
              ...values,
              'id': id,
              'created_at': now,
              if (table == 'cases' || table == 'dak_register') 'updated_at': now,
            }, conflictAlgorithm: ConflictAlgorithm.abort);

            for (final entry in customValues.entries) {
              await txn.insert('custom_field_values', {
                'id': '${table}_${id}_${entry.key}',
                'module': table,
                'record_id': id,
                'field_id': entry.key,
                'value': entry.value,
                'updated_at': now,
              }, conflictAlgorithm: ConflictAlgorithm.replace);
            }
            await txn.execute('RELEASE SAVEPOINT $savepoint');
            imported++;
          } catch (_) {
            await txn.execute('ROLLBACK TO SAVEPOINT $savepoint');
            await txn.execute('RELEASE SAVEPOINT $savepoint');
            rethrow;
          }
        } catch (error) {
          errors++;
          await recordIssue(index, 'error', error.toString(), source);
        }
      }

      await _insertAudit(txn, 'BULK_IMPORT_COMPLETED', table, '',
        'import_id=$importId; source=$sourceName; imported=$imported; skipped=$skipped; errors=$errors');
      await txn.insert('import_history', {
        'id': importId,
        'module': table,
        'source_name': sourceName,
        'file_name': sourceName,
        'total_rows': rows.length + preRejectedRows.length,
        'imported_rows': imported,
        'skipped_rows': skipped,
        'error_rows': errors,
        'created_at': now,
        'imported_at': now,
        'details': 'row-level report: import_row_errors',
      });
    });
    return {'total': rows.length + preRejectedRows.length, 'imported': imported, 'skipped': skipped, 'errors': errors};
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


  Future<List<Map<String, Object?>>> evidenceItems({String? caseId}) async {
    final db = await database;
    if (caseId == null) {
      return db.rawQuery('''
        SELECT e.*, c.st_no, c.fir_no, c.accused_name
        FROM evidence_items e
        JOIN cases c ON c.id = e.case_id
        ORDER BY e.updated_at DESC
      ''');
    }
    return db.query('evidence_items', where: 'case_id = ?', whereArgs: [caseId], orderBy: 'updated_at DESC');
  }

  Future<void> saveEvidence(Map<String, Object?> values, {String? id}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    if (id == null) {
      await db.insert('evidence_items', {
        ...values,
        'created_at': now,
        'updated_at': now,
      });
    } else {
      await db.update('evidence_items', {...values, 'updated_at': now},
          where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<void> deleteEvidence(String id) async {
    final db = await database;
    await db.delete('evidence_items', where: 'id = ?', whereArgs: [id]);
  }

  /// Searches all primary registers without changing or copying stored records.
  Future<List<Map<String, Object?>>> globalSearch(String query) async {
    final db = await database;
    final q = query.trim();
    if (q.length < 2) return [];
    final like = '%$q%';
    return db.rawQuery('''
      SELECT * FROM (
        SELECT 'मुकदमा' AS record_type, c.id AS record_id,
          COALESCE(c.st_no, '') AS title,
          'FIR: ' || COALESCE(c.fir_no, '') || ' • ' ||
          COALESCE(c.accused_name, '') AS subtitle,
          COALESCE(c.court_name, '') AS detail,
          COALESCE(c.updated_at, '') AS sort_date
        FROM cases c
        WHERE c.is_archived = 0 AND (
          c.st_no LIKE ? OR c.fir_no LIKE ? OR c.accused_name LIKE ? OR
          c.sections LIKE ? OR c.court_name LIKE ? OR c.summoned_witnesses LIKE ?
        )
        UNION ALL
        SELECT 'डाक' AS record_type, d.id AS record_id,
          'ST No. ' || COALESCE(d.st_no, '') AS title,
          COALESCE(d.dak_type, '') || ' • ' || COALESCE(d.accused_name, '') AS subtitle,
          COALESCE(d.court_name, '') || ' • ' || COALESCE(d.remarks, '') AS detail,
          COALESCE(d.updated_at, d.created_at, '') AS sort_date
        FROM dak_register d
        WHERE d.st_no LIKE ? OR d.accused_name LIKE ? OR d.status LIKE ? OR
          d.dak_type LIKE ? OR d.person_address LIKE ? OR d.related_station LIKE ? OR
          d.court_name LIKE ? OR d.remarks LIKE ?
        UNION ALL
        SELECT 'रिमांड' AS record_type, r.id AS record_id,
          'FIR No. ' || COALESCE(r.fir_no, '') AS title,
          COALESCE(r.accused_details, '') AS subtitle,
          COALESCE(r.sections, '') || ' • ' || COALESCE(r.court_name, '') ||
          ' • ' || COALESCE(r.investigating_officer, '') AS detail,
          COALESCE(r.remand_date, r.created_at, '') AS sort_date
        FROM remand_register r
        WHERE r.fir_no LIKE ? OR r.sections LIKE ? OR r.court_name LIKE ? OR
          r.investigating_officer LIKE ? OR r.accused_details LIKE ?
        UNION ALL
        SELECT 'संपर्क' AS record_type, a.id AS record_id,
          a.name AS title,
          COALESCE(a.department, '') || ' • ' || COALESCE(a.mobile, '') AS subtitle,
          COALESCE(a.address, '') AS detail,
          COALESCE(a.created_at, '') AS sort_date
        FROM address_book a
        WHERE a.name LIKE ? OR a.mobile LIKE ? OR a.department LIKE ? OR a.address LIKE ?
        UNION ALL
        SELECT 'दस्तावेज' AS record_type, d.id AS record_id,
          d.name AS title,
          COALESCE(d.category, '') || ' • ST No. ' || COALESCE(c.st_no, '') AS subtitle,
          COALESCE(d.remarks, '') AS detail,
          COALESCE(d.created_at, '') AS sort_date
        FROM case_documents d
        LEFT JOIN cases c ON c.id = d.case_id
        WHERE d.name LIKE ? OR d.category LIKE ? OR d.remarks LIKE ? OR
          c.st_no LIKE ? OR c.fir_no LIKE ? OR c.accused_name LIKE ?
      ) results
      ORDER BY sort_date DESC
      LIMIT 200
    ''', [
      like, like, like, like, like, like,
      like, like, like, like, like, like, like, like,
      like, like, like, like, like,
      like, like, like, like,
      like, like, like, like, like, like,
    ]);
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


  /// Atomically changes a primary record and records the corresponding audit event.
  /// An audit failure rolls back the record mutation instead of reporting a false save failure.
  Future<void> saveWithAudit({
    required String table,
    required Map<String, Object?> values,
    required String recordId,
    required bool isNew,
    required String action,
    required String module,
    required String details,
    Map<String, String> customFieldValues = const {},
    String? customFieldModule,
  }) async {
    const allowed = {'cases', 'dak_register', 'remand_register', 'address_book', 'evidence_items'};
    if (!allowed.contains(table)) throw ArgumentError('Unsupported table: $table');
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      if (isNew) {
        await txn.insert(table, {
          ...values,
          'id': recordId,
          'created_at': now,
          if (table == 'cases' || table == 'evidence_items' ||
              table == 'dak_register') 'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      } else {
        final changed = await txn.update(table, {
          ...values,
          if (table == 'cases' || table == 'evidence_items' ||
              table == 'dak_register') 'updated_at': now,
        }, where: 'id = ?', whereArgs: [recordId]);
        if (changed != 1) throw StateError('Record not found for update');
      }
      for (final entry in customFieldValues.entries) {
        final fieldModule = customFieldModule ?? module;
        await txn.insert('custom_field_values', {
          'id': '${fieldModule}_${recordId}_${entry.key}',
          'module': fieldModule, 'record_id': recordId,
          'field_id': entry.key, 'value': entry.value,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await _insertAudit(txn, action, module, recordId, details);
    });
  }

  Future<void> archiveCaseWithAudit(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      final changed = await txn.update('cases', {
        'is_archived': 1, 'updated_at': DateTime.now().toIso8601String(),
      }, where: 'id = ?', whereArgs: [id]);
      if (changed != 1) throw StateError('Case not found for archive');
      await _insertAudit(txn, 'CASE_ARCHIVED', 'SESSION_COURT', id, 'Soft archive');
    });
  }

  Future<void> deleteEvidenceWithAudit(String id, String description) async {
    final db = await database;
    await db.transaction((txn) async {
      final changed = await txn.delete('evidence_items', where: 'id = ?', whereArgs: [id]);
      if (changed != 1) throw StateError('Evidence record not found');
      await _insertAudit(txn, 'EVIDENCE_RECORD_DELETED', 'EVIDENCE', id, description);
    });
  }

  Future<void> _insertAudit(DatabaseExecutor txn, String action,
      String module, String recordId, String details) async {
    final now = DateTime.now();
    await txn.insert('audit_log', {
      'id': '${now.microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
      'action': action, 'module': module, 'record_id': recordId,
      'details': details, 'created_at': now.toIso8601String(),
    });
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
    await db.transaction((txn) async {
      await txn.insert('case_timeline', {
        'id': id, 'case_id': caseId, 'event_date': date,
        'event_type': type, 'description': description,
        'created_at': DateTime.now().toIso8601String(),
      });
      await _insertAudit(txn, 'TIMELINE_ADDED', 'CASE_TIMELINE', id, '$type: $description');
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
    await db.transaction((txn) async {
      await txn.insert('case_checklist', {
        'id': id, 'case_id': caseId, 'task_name': task,
        'status': 'लंबित', 'due_date': dueDate, 'assigned_to': assignedTo,
        'remarks': remarks, 'updated_at': DateTime.now().toIso8601String(),
      });
      await _insertAudit(txn, 'CHECKLIST_ADDED', 'CASE_CHECKLIST', id, task);
    });
  }

  Future<void> setChecklistStatus(String id, bool done) async {
    final db = await database;
    await db.transaction((txn) async {
      final changed = await txn.update('case_checklist', {
        'status': done ? 'पूर्ण' : 'लंबित',
        'completed_date': done ? DateTime.now().toIso8601String() : '',
        'updated_at': DateTime.now().toIso8601String(),
      }, where: 'id = ?', whereArgs: [id]);
      if (changed != 1) throw StateError('Checklist task not found');
      final rows = await txn.query('case_checklist',
          columns: ['task_name'], where: 'id = ?', whereArgs: [id], limit: 1);
      final taskName = rows.isEmpty ? id : (rows.first['task_name'] ?? id).toString();
      await _insertAudit(txn, done ? 'TASK_COMPLETED' : 'TASK_REOPENED',
          'CASE_CHECKLIST', id, taskName);
    });
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
      await _insertAudit(txn, 'DOCUMENT_ATTACHED', 'CASE_DOCUMENTS', id, name);
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
      final changed = await txn.update('case_documents', {
        'version': version, 'local_path': path, 'remarks': 'नवीनतम संस्करण',
      }, where: 'id = ?', whereArgs: [documentId]);
      if (changed != 1) throw StateError('Document not found for version update');
      await _insertAudit(txn, 'DOCUMENT_VERSION_ADDED', 'CASE_DOCUMENTS',
          documentId, 'Version $version: $remarks');
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
