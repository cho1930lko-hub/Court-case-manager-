class ParsedImportSheet {
  const ParsedImportSheet({
    required this.headers,
    required this.rows,
    required this.sourceRowNumbers,
  });

  final List<String> headers;
  final List<List<String>> rows;
  final List<int> sourceRowNumbers;
}

/// Pure import rules shared by the UI and automated tests.
class ImportValidation {
  static const dateColumns = <String>{
    'next_hearing', 'previous_hearing', 'fir_date', 'charge_sheet_date',
    'cognizance_date', 'charge_framed_date', 'station_received_date',
    'hearing_date', 'remand_date', 'first_remand_date',
  };

  static String normalizeHeader(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9ऀ-ॿ]+'), '').trim();

  static ParsedImportSheet parseRows(List<List<String>> source) {
    if (source.length < 2 || !source.first.any((value) => value.trim().isNotEmpty)) {
      throw const FormatException('शीट में हेडर और कम-से-कम एक डेटा पंक्ति होनी चाहिए।');
    }
    final headers = List<String>.from(source.first);
    final rows = <List<String>>[];
    final sourceRowNumbers = <int>[];
    for (var index = 1; index < source.length; index++) {
      final row = source[index];
      if (!row.any((value) => value.trim().isNotEmpty)) continue;
      rows.add(List.generate(headers.length, (column) =>
          column < row.length ? row[column] : ''));
      sourceRowNumbers.add(index + 1);
    }
    if (rows.isEmpty) {
      throw const FormatException('शीट में कोई डेटा पंक्ति नहीं है।');
    }
    return ParsedImportSheet(
      headers: headers,
      rows: rows,
      sourceRowNumbers: sourceRowNumbers,
    );
  }

  static bool isValidDateValue(String column, String value) {
    final raw = value.trim();
    if (!dateColumns.contains(column) || raw.isEmpty) return true;
    final indian = RegExp(r'^(\\d{1,2})[./-](\\d{1,2})[./-](\\d{4})$').firstMatch(raw);
    final iso = RegExp(r'^(\\d{4})-(\\d{1,2})-(\\d{1,2})$').firstMatch(raw);
    if (indian == null && iso == null) return false;
    final year = int.parse(indian != null ? indian.group(3)! : iso!.group(1)!);
    final month = int.parse(indian != null ? indian.group(2)! : iso!.group(2)!);
    final day = int.parse(indian != null ? indian.group(1)! : iso!.group(3)!);
    if (year < 1900 || month < 1 || month > 12 || day < 1) return false;
    final parsed = DateTime(year, month, day);
    return parsed.year == year && parsed.month == month && parsed.day == day;
  }

  static String? validateRow(String module, Map<String, Object?> row) {
    String value(String field) => (row[field] ?? '').toString().trim();
    switch (module) {
      case 'cases':
        if (value('st_no').isEmpty) return 'ST No. आवश्यक है';
      case 'dak_register':
        if (value('st_no').isEmpty || value('dak_type').isEmpty) {
          return 'Dak के लिए STN और Type दोनों आवश्यक हैं';
        }
      case 'remand_register':
        if (value('fir_no').isEmpty || value('remand_date').isEmpty) {
          return 'रिमांड के लिए FIR नंबर और रिमांड दिनांक दोनों आवश्यक हैं';
        }
      case 'address_book':
        if (value('mobile').isEmpty) return 'मोबाइल नंबर आवश्यक है';
        if (value('name').isEmpty) return 'नाम आवश्यक है';
      default:
        if (!{'cases', 'dak_register', 'remand_register', 'address_book'}.contains(module)) {
          return 'अज्ञात मॉड्यूल';
        }
    }
    if (value('total_witnesses').isNotEmpty &&
        int.tryParse(value('total_witnesses')) == null) {
      return 'कुल गवाह संख्या गलत है';
    }
    for (final entry in row.entries) {
      if (!isValidDateValue(entry.key, (entry.value ?? '').toString())) {
        return '${entry.key}: तारीख का प्रारूप अमान्य है';
      }
    }
    return null;
  }

  static List<String> identityFields(String module) => switch (module) {
    'cases' => const ['st_no'],
    'dak_register' => const ['st_no', 'dak_type'],
    'remand_register' => const ['fir_no', 'remand_date'],
    'address_book' => const ['mobile'],
    _ => const [],
  };

  static String identityKey(String module, Map<String, Object?> row) {
    final fields = identityFields(module);
    if (fields.isEmpty) return '';
    final values = fields.map((field) => (row[field] ?? '').toString().trim().toLowerCase()).toList();
    if (values.any((value) => value.isEmpty)) return '';
    return values.join('|');
  }
}
