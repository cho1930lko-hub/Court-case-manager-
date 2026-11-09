import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';

import '../data/local_database.dart';

class ImportPreview {
  const ImportPreview({required this.headers, required this.rows, required this.mapping,
    required this.duplicates, required this.invalid});
  final List<String> headers;
  final List<List<String>> rows;
  final Map<String, String> mapping;
  final Set<int> duplicates;
  final Map<int, String> invalid;
}

class DataManagementService {
  DataManagementService._();
  static final instance = DataManagementService._();

  static const modules = <String, String>{
    'cases': 'सेशन कोर्ट', 'dak_register': 'डाक',
    'remand_register': 'रिमांड', 'address_book': 'Address Book',
  };

  static const aliases = <String, Map<String, List<String>>>{
    'cases': {
      'st_no': ['st no', 'stno', 'क्रमांक'], 'fir_no': ['मु0अ0स0', 'मु.अ.सं.', 'fir no'],
      'sections': ['धारा', 'sections'], 'accused_name': ['राज्य बनाम', 'अभियुक्त', 'accused'],
      'court_name': ['न्यायालय', 'court'], 'summoned_witnesses': ['तलब साक्षी', 'गवाह'],
      'next_hearing': ['तारीख पेशी', 'अगली पेशी', 'next hearing'],
      'previous_hearing': ['पिछली पेशी', 'previous hearing'], 'status': ['status', 'स्थिति'],
      'summons_status': ['सम्मन की स्थिति', 'summons status'],
      'monitoring_type': ['type of moni', 'monitoring type'], 'action_taken': ['कृत कार्यवाही', 'action taken'],
      'total_witnesses': ['कुल गवाह', 'total witnesses'], 'fir_date': ['fir दिनांक', 'fir date'],
      'charge_sheet_date': ['आरोप पत्र प्रेषित', 'charge sheet date'],
      'cognizance_date': ['प्रसंज्ञान दिनांक', 'cognizance date'],
      'charge_framed_date': ['चार्ज फ्रेम', 'charge framed'],
      'station_received_date': ['थाने पर देने का दिनाँक', 'थाने पर देने का दिनांक'],
    },
    'dak_register': {
      'st_no': ['st no', 'stno'], 'accused_name': ['राज्य बनाम', 'अभियुक्त', 'नाम'],
      'status': ['स्थिति', 'status'], 'dak_type': ['डाक का प्रकार', 'dak type', 'type'],
      'person_address': ['पता', 'address'], 'related_station': ['थाना', 'related station'],
      'court_name': ['न्यायालय', 'court'], 'station_received_date': ['प्राप्ति दिनांक', 'थाने पर देने का दिनांक'],
      'hearing_date': ['पेशी दिनांक', 'hearing date'], 'remarks': ['टिप्पणी', 'विवरण', 'remarks'],
    },
    'remand_register': {
      'remand_date': ['रिमांड दिनांक', 'remand date', 'दिनांक'], 'fir_no': ['मु0अ0स0', 'fir no'],
      'sections': ['धारा', 'sections'], 'court_name': ['न्यायालय', 'court'],
      'investigating_officer': ['विवेचक', 'investigating officer', 'io'],
      'first_remand_date': ['प्रथम रिमांड', 'first remand date'],
      'accused_details': ['अभियुक्त विवरण', 'अभियुक्त', 'accused details'],
    },
    'address_book': {
      'name': ['नाम', 'name', 'अधिकारी का नाम'], 'address': ['पता', 'address'],
      'mobile': ['मोबाइल', 'मोबाइल नंबर', 'mobile', 'phone'],
      'department': ['विभाग', 'थाना', 'department'],
    },
  };

  String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[\\s._:/()\\-]+'), '');
  Map<String, String> autoMatch(String module, List<String> headers) {
    final result = <String, String>{};
    for (final entry in (aliases[module] ?? {}).entries) {
      final candidates = [entry.key, ...entry.value].map(_norm).toSet();
      for (final header in headers) {
        if (candidates.contains(_norm(header))) { result[entry.key] = header; break; }
      }
    }
    return result;
  }

  List<List<String>> readWorkbook(Uint8List bytes) {
    final workbook = Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) throw const FormatException('Excel में कोई शीट नहीं मिली।');
    final rows = workbook.tables.values.first.rows.map((r) =>
      r.map((c) => c?.value?.toString().trim() ?? '').toList()).toList();
    while (rows.isNotEmpty && rows.last.every((v) => v.isEmpty)) { rows.removeLast(); }
    if (rows.length < 2) throw const FormatException('हेडर के बाद कोई डेटा नहीं मिला।');
    return rows;
  }

  String _key(String module, Map<String, Object?> row) {
    final cols = switch (module) {
      'cases' => ['st_no'], 'dak_register' => ['st_no', 'dak_type'],
      'remand_register' => ['fir_no', 'remand_date'], _ => ['mobile', 'name'],
    };
    final values = cols.map((c) => (row[c] ?? '').toString().trim().toLowerCase()).toList();
    return values.every((v) => v.isEmpty) ? '' : values.join('|');
  }

  String _date(String value) {
    final match = RegExp(r'^(\\d{1,2})[/.-](\\d{1,2})[/.-](\\d{4})$').firstMatch(value.trim());
    if (match == null) return value;
    final d = match.group(1)!.padLeft(2, '0');
    final m = match.group(2)!.padLeft(2, '0');
    return '${match.group(3)}-$m-$d';
  }

  Future<ImportPreview> preview(String module, List<List<String>> source, Map<String, String> mapping) async {
    final headers = source.first;
    final existing = await LocalDatabase.instance.exportRegisterRows(module);
    final known = existing.map((r) => _key(module, r)).where((k) => k.isNotEmpty).toSet();
    final seen = <String>{};
    final duplicates = <int>{};
    final invalid = <int, String>{};
    final rows = source.skip(1).toList();
    for (var i = 0; i < rows.length; i++) {
      final values = <String, Object?>{};
      for (final entry in mapping.entries) {
        final col = headers.indexOf(entry.value);
        if (col >= 0 && col < rows[i].length) values[entry.key] = rows[i][col].trim();
      }
      final key = _key(module, values);
      if (key.isEmpty) invalid[i + 2] = 'मुख्य पहचान वाला कॉलम खाली है';
      else if (known.contains(key) || !seen.add(key)) duplicates.add(i + 2);
      if (module == 'cases' && (values['st_no'] ?? '').toString().isEmpty) invalid[i + 2] = 'ST No. आवश्यक है';
      if (module == 'address_book' && (values['name'] ?? '').toString().isEmpty) invalid[i + 2] = 'नाम आवश्यक है';
      if (values.containsKey('total_witnesses') &&
          int.tryParse(values['total_witnesses'].toString()) == null) invalid[i + 2] = 'कुल गवाह संख्या गलत है';
    }
    return ImportPreview(headers: headers, rows: rows, mapping: mapping, duplicates: duplicates, invalid: invalid);
  }

  Future<Map<String, int>> importRows(String module, String fileName, ImportPreview preview, Set<int> selected) async {
    final columns = await LocalDatabase.instance.importableColumns(module);
    final data = <Map<String, Object?>>[];
    for (var i = 0; i < preview.rows.length; i++) {
      final rowNo = i + 2;
      if (!selected.contains(rowNo) || preview.duplicates.contains(rowNo) || preview.invalid.containsKey(rowNo)) continue;
      final values = <String, Object?>{};
      for (final entry in preview.mapping.entries) {
        if (!columns.contains(entry.key)) continue;
        final index = preview.headers.indexOf(entry.value);
        if (index < 0 || index >= preview.rows[i].length) continue;
        var value = preview.rows[i][index].trim();
        if (value.isEmpty) continue;
        if (entry.key.endsWith('_date') || entry.key.contains('hearing') || entry.key == 'station_received_date') value = _date(value);
        if (entry.key == 'total_witnesses') values[entry.key] = int.parse(value);
        else values[entry.key] = value;
      }
      data.add(values);
    }
    return LocalDatabase.instance.importRegisterRows(module, data, sourceName: fileName);
  }
}
