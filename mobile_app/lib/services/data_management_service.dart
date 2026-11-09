import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:uuid/uuid.dart';

import '../data/local_database.dart';

class ImportPreview {
  const ImportPreview({
    required this.headers,
    required this.rows,
    required this.matchedColumns,
    required this.duplicateRows,
    required this.invalidRows,
  });
  final List<String> headers;
  final List<List<String>> rows;
  final Map<String, String> matchedColumns;
  final Set<int> duplicateRows;
  final Map<int, String> invalidRows;
}

class DataManagementService {
  DataManagementService._();
  static final instance = DataManagementService._();
  static const _uuid = Uuid();

  static const modules = <String, String>{
    'cases': 'सेशन कोर्ट',
    'dak_register': 'डाक',
    'remand_register': 'रिमांड',
    'address_book': 'Address Book',
  };

  static const aliases = <String, Map<String, List<String>>>{
    'cases': {
      'st_no': ['st no', 'stno', 'क्रमांक', 'सेशन ट्रायल', 'session trial'],
      'fir_no': ['मु0अ0स0', 'मु.अ.सं.', 'fir no', 'crime number'],
      'sections': ['धारा', 'sections'],
      'accused_name': ['राज्य बनाम', 'अभियुक्त', 'accused', 'case title'],
      'court_name': ['न्यायालय', 'court', 'court name'],
      'summoned_witnesses': ['तलब साक्षी', 'गवाह', 'summoned witnesses'],
      'next_hearing': ['तारीख पेशी', 'अगली पेशी', 'next hearing'],
      'previous_hearing': ['पिछली पेशी', 'previous hearing'],
      'status': ['status', 'स्थिति'],
      'summons_status': ['सम्मन की स्थिति', 'summons status'],
      'monitoring_type': ['type of moni', 'monitoring type'],
      'action_taken': ['कृत कार्यवाही', 'action taken'],
      'total_witnesses': ['कुल गवाह', 'total witnesses'],
      'fir_date': ['fir दिनांक', 'fir date'],
      'charge_sheet_date': ['आरोप पत्र प्रेषित', 'charge sheet date'],
      'cognizance_date': ['प्रसंज्ञान दिनांक', 'cognizance date'],
      'charge_framed_date': ['चार्ज फ्रेम', 'charge framed'],
      'station_received_date': ['थाने पर देने का दिनाँक', 'थाने पर देने का दिनांक'],
    },
    'dak_register': {
      'st_no': ['st no', 'stno', 'सेशन ट्रायल'],
      'accused_name': ['राज्य बनाम', 'अभियुक्त', 'नाम'],
      'status': ['स्थिति', 'status'],
      'dak_type': ['डाक का प्रकार', 'dak type', 'type'],
      'person_address': ['पता', 'address'],
      'related_station': ['थाना', 'related station'],
      'court_name': ['न्यायालय', 'court'],
      'station_received_date': ['प्राप्ति दिनांक', 'थाने पर देने का दिनांक'],
      'hearing_date': ['पेशी दिनांक', 'hearing date'],
      'remarks': ['टिप्पणी', 'विवरण', 'remarks'],
    },
    'remand_register': {
      'remand_date': ['रिमांड दिनांक', 'remand date', 'दिनांक'],
      'fir_no': ['मु0अ0स0', 'fir no', 'crime number'],
      'sections': ['धारा', 'sections'],
      'court_name': ['न्यायालय', 'court'],
      'investigating_officer': ['विवेचक', 'investigating officer', 'io'],
      'first_remand_date': ['प्रथम रिमांड', 'first remand date'],
      'accused_details': ['अभियुक्त विवरण', 'अभियुक्त', 'accused details'],
    },
    'address_book': {
      'name': ['नाम', 'name', 'अधिकारी का नाम'],
      'address': ['पता', 'address'],
      'mobile': ['मोबाइल', 'मोबाइल नंबर', 'mobile', 'phone'],
      'department': ['विभाग', 'थाना', 'department'],
    },
  };

  String _normal(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[\\s._:/()\\-]+'), '')
      .replaceAll('०', '0').replaceAll('१', '1');

  Map<String, String> autoMatch(String module, List<String> headers) {
    final result = <String, String>{};
    final fields = aliases[module] ?? const <String, List<String>>{};
    for (final entry in fields.entries) {
      final candidates = [entry.key, ...entry.value].map(_normal).toSet();
      for (final header in headers) {
        if (candidates.contains(_normal(header))) {
          result[entry.key] = header;
          break;
        }
      }
    }
    return result;
  }

  List<List<String>> readWorkbook(Uint8List bytes) {
    final book = Excel.decodeBytes(bytes);
    if (book.tables.isEmpty) throw const FormatException('Excel फाइल में कोई शीट नहीं मिली।');
    final sheet = book.tables.values.first;
    final rows = sheet.rows.map((row) => row
        .map((cell) => cell?.value?.toString().trim() ?? '')
        .toList(growable: false)).toList();
    while (rows.isNotEmpty && rows.last.every((cell) => cell.isEmpty)) {
      rows.removeLast();
    }
    if (rows.length < 2) throw const FormatException('फाइल में हेडर के बाद कोई रिकॉर्ड नहीं है।');
    return rows;
  }

  Future<ImportPreview> preview({
    required String module,
    required List<List<String>> sourceRows,
    required Map<String, String> mapping,
  }) async {
    if (!modules.containsKey(module)) throw ArgumentError('अमान्य मॉड्यूल');
    final headers = sourceRows.first;
    final dataRows = sourceRows.skip(1).toList();
    final db = await LocalDatabase.instance.database;
    final existing = await db.query(module, columns: _keyColumns(module));
    final keys = existing.map((row) => _duplicateKey(module, row)).toSet();
    final seen = <String>{};
    final duplicates = <int>{};
    final invalid = <int, String>{};
    for (var i = 0; i < dataRows.length; i++) {
      final row = dataRows[i];
      final values = <String, String>{};
      for (final entry in mapping.entries) {
        final index = headers.indexOf(entry.value);
        if (index >= 0 && index < row.length) values[entry.key] = row[index].trim();
      }
      final key = _duplicateKey(module, values);
      if (key.isEmpty) {
        invalid[i + 2] = 'मुख्य पहचान वाला कॉलम खाली है';
      } else if (keys.contains(key) || !seen.add(key)) {
        duplicates.add(i + 2);
      }
      if (module == 'cases' && (values['st_no'] ?? '').isEmpty) {
        invalid[i + 2] = 'ST No. आवश्यक है';
      }
      if (module == 'address_book' && (values['name'] ?? '').isEmpty) {
        invalid[i + 2] = 'नाम आवश्यक है';
      }
    }
    return ImportPreview(headers: headers, rows: dataRows,
      matchedColumns: mapping, duplicateRows: duplicates, invalidRows: invalid);
  }

  List<String> _keyColumns(String module) => switch (module) {
    'cases' => ['st_no'], 'dak_register' => ['st_no', 'dak_type'],
    'remand_register' => ['fir_no', 'remand_date'],
    _ => ['name', 'mobile'],
  };

  String _duplicateKey(String module, Map<String, Object?> row) {
    final values = _keyColumns(module).map((key) => (row[key] ?? '').toString().trim().toLowerCase());
    final parts = values.toList();
    if (parts.every((part) => part.isEmpty)) return '';
    return parts.join('|');
  }

  Future<Map<String, int>> importRows({
    required String module,
    required String fileName,
    required ImportPreview preview,
    required Map<String, String> mapping,
    required Set<int> selectedRows,
  }) async {
    final db = await LocalDatabase.instance.database;
    final tableInfo = await db.rawQuery('PRAGMA table_info($module)');
    final allowed = tableInfo.map((e) => e['name'].toString()).toSet()
      ..removeAll({'id', 'created_at', 'updated_at', 'is_archived'});
    final now = DateTime.now().toIso8601String();
    var imported = 0, skipped = 0, errors = 0;
    final historyId = _uuid.v4();
    await db.transaction((txn) async {
      for (var i = 0; i < preview.rows.length; i++) {
        final rowNumber = i + 2;
        if (!selectedRows.contains(rowNumber)) { skipped++; continue; }
        if (preview.invalidRows.containsKey(rowNumber) ||
            preview.duplicateRows.contains(rowNumber)) { skipped++; continue; }
        try {
          final values = <String, Object?>{};
          for (final entry in mapping.entries) {
            if (!allowed.contains(entry.key)) continue;
            final index = preview.headers.indexOf(entry.value);
            if (index < 0 || index >= preview.rows[i].length) continue;
            var value = preview.rows[i][index].trim();
            if (value.isEmpty) continue;
            if (entry.key == 'total_witnesses') {
              final parsed = int.tryParse(value);
              if (parsed == null || parsed < 0) throw FormatException('पंक्ति $rowNumber: कुल गवाह संख्या गलत है');
              values[entry.key] = parsed;
            } else {
              values[entry.key] = value;
            }
          }
          final id = _uuid.v4();
          values['id'] = id;
          values['created_at'] = now;
          if (allowed.contains('updated_at')) values['updated_at'] = now;
          await txn.insert(module, values);
          await txn.insert('audit_log', {
            'id': _uuid.v4(), 'action': 'BULK_IMPORT', 'module': module,
            'record_id': id, 'details': 'Imported from $fileName, row $rowNumber',
            'created_at': now,
          });
          imported++;
        } on FormatException {
          errors++;
        } catch (_) {
          errors++;
        }
      }
      await txn.insert('import_history', {
        'id': historyId, 'module': module, 'file_name': fileName,
        'total_rows': preview.rows.length, 'imported_rows': imported,
        'skipped_rows': skipped, 'error_rows': errors,
        'imported_at': now,
        'details': 'Auto mapping: ${mapping.length} fields; duplicates are skipped.',
      });
    });
    return {'imported': imported, 'skipped': skipped, 'errors': errors};
  }

  Future<List<Map<String, Object?>>> fields(String module) async {
    final db = await LocalDatabase.instance.database;
    return db.query('field_definitions', where: 'module = ?', whereArgs: [module],
      orderBy: 'sort_order, label');
  }

  Future<void> saveField({
    String? id, required String module, required String key, required String label,
    required String type, required bool requiredField, required bool dropdown,
    required List<String> options,
  }) async {
    if (!modules.containsKey(module)) throw ArgumentError('अमान्य मॉड्यूल');
    final db = await LocalDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    final fieldId = id ?? _uuid.v4();
    await db.transaction((txn) async {
      await txn.insert('field_definitions', {
        'id': fieldId, 'module': module, 'field_key': key.trim(),
        'label': label.trim(), 'data_type': type,
        'is_required': requiredField ? 1 : 0, 'is_dropdown': dropdown ? 1 : 0,
        'is_active': 1, 'sort_order': 0, 'created_at': now, 'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.delete('field_options', where: 'field_id = ?', whereArgs: [fieldId]);
      for (var i = 0; i < options.length; i++) {
        if (options[i].trim().isEmpty) continue;
        await txn.insert('field_options', {
          'id': _uuid.v4(), 'field_id': fieldId,
          'option_label': options[i].trim(), 'sort_order': i,
          'is_active': 1, 'created_at': now,
        });
      }
    });
  }

  Future<void> setFieldPermission({
    required String module, required String fieldId, required String role,
    required bool canView, required bool canEdit,
  }) async {
    final db = await LocalDatabase.instance.database;
    await db.insert('field_permissions', {
      'id': _uuid.v4(), 'module': module, 'field_id': fieldId, 'role': role,
      'can_view': canView ? 1 : 0, 'can_edit': canEdit ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> importHistory() async {
    final db = await LocalDatabase.instance.database;
    return db.query('import_history', orderBy: 'imported_at DESC', limit: 100);
  }

  Future<String> exportCsv(String module) async {
    if (!modules.containsKey(module)) throw ArgumentError('अमान्य मॉड्यूल');
    final db = await LocalDatabase.instance.database;
    final rows = await db.query(module);
    if (rows.isEmpty) return '';
    final headers = rows.first.keys.toList();
    String quote(Object? value) {
      final s = (value ?? '').toString().replaceAll('"', '""');
      return '"$s"';
    }
    return '\uFEFF${[headers.map(quote).join(','), ...rows.map((row) => headers.map((h) => quote(row[h])).join(','))].join('\\r\\n')}';
  }
}
