import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart';
import 'package:court_case_manager/services/import_validation.dart';

void main() {
  group('ImportValidation identity rules', () {
    test('Session Court requires ST NO and preserves leading zeroes', () {
      expect(ImportValidation.validateRow('cases', {'st_no': '0012'}), isNull);
      expect(ImportValidation.identityKey('cases', {'st_no': '0012'}), '0012');
      expect(ImportValidation.validateRow('cases', {'st_no': ''}), isNotNull);
    });

    test('Dak requires both STN and Type', () {
      expect(ImportValidation.validateRow('dak_register',
          {'st_no': 'D-1', 'dak_type': 'सम्मन'}), isNull);
      expect(ImportValidation.validateRow('dak_register',
          {'st_no': 'D-1', 'dak_type': ''}), isNotNull);
      expect(ImportValidation.identityKey('dak_register',
          {'st_no': 'D-1', 'dak_type': ''}), isEmpty);
    });

    test('Rimand requires FIR number and remand date', () {
      expect(ImportValidation.validateRow('remand_register',
          {'fir_no': '123/26', 'remand_date': '10/11/2026'}), isNull);
      expect(ImportValidation.validateRow('remand_register',
          {'fir_no': '123/26'}), isNotNull);
    });

    test('Address Book requires mobile and name', () {
      expect(ImportValidation.validateRow('address_book',
          {'mobile': '9876543210', 'name': 'अमित'}), isNull);
      expect(ImportValidation.validateRow('address_book',
          {'mobile': '', 'name': 'अमित'}), isNotNull);
      expect(ImportValidation.validateRow('address_book',
          {'mobile': '9876543210', 'name': ''}), isNotNull);
    });
  });

  group('ImportValidation date and row rules', () {
    test('accepts valid Indian and ISO dates; rejects impossible dates', () {
      expect(ImportValidation.isValidDateValue('fir_date', '29/02/2024'), isTrue);
      expect(ImportValidation.isValidDateValue('fir_date', '2024-02-29'), isTrue);
      expect(ImportValidation.isValidDateValue('fir_date', '31/02/2024'), isFalse);
      expect(ImportValidation.isValidDateValue('fir_date', 'date unknown'), isFalse);
      expect(ImportValidation.isValidDateValue('fir_date', ''), isTrue);
    });

    test('blank optional witness count is allowed; invalid number is rejected', () {
      expect(ImportValidation.validateRow('cases',
          {'st_no': '1', 'total_witnesses': ''}), isNull);
      expect(ImportValidation.validateRow('cases',
          {'st_no': '1', 'total_witnesses': 'many'}), isNotNull);
    });

    test('normalizes Hindi and English headers consistently', () {
      expect(ImportValidation.normalizeHeader(' ST NO '), 'stno');
      expect(ImportValidation.normalizeHeader('अगली तारीख पेशी'),
          ImportValidation.normalizeHeader('अगली-तारीख-पेशी'));
    });
  });

  group('Import workbook parsing', () {
    test('keeps original worksheet row numbers and ignores blank rows', () {
      final parsed = ImportValidation.parseRows([
        ['ST NO', 'बनाम'],
        ['001', 'पहला'],
        ['', ''],
        ['002', 'दूसरा'],
      ]);
      expect(parsed.headers, ['ST NO', 'बनाम']);
      expect(parsed.rows, [['001', 'पहला'], ['002', 'दूसरा']]);
      expect(parsed.sourceRowNumbers, [2, 4]);
    });

    test('round-trips a synthetic multi-sheet XLSX workbook', () {
      final workbook = Excel.createExcel();
      workbook['सेशन कोर्ट'].appendRow([
        TextCellValue('ST NO'), TextCellValue('बनाम'),
      ]);
      workbook['सेशन कोर्ट'].appendRow([
        TextCellValue('001'), TextCellValue('राज्य बनाम A'),
      ]);
      workbook['डाक'].appendRow([
        TextCellValue('STN'), TextCellValue('Type'),
      ]);
      workbook['डाक'].appendRow([
        TextCellValue('D-1'), TextCellValue('सम्मन'),
      ]);
      final bytes = workbook.encode();
      expect(bytes, isNotNull);
      final decoded = Excel.decodeBytes(bytes!);
      expect(decoded.tables.keys, containsAll(['सेशन कोर्ट', 'डाक']));
      final selected = decoded.tables['डाक']!;
      final sourceRows = selected.rows.map((row) =>
          row.map((cell) => cell?.value?.toString() ?? '').toList()).toList();
      final parsed = ImportValidation.parseRows(sourceRows);
      expect(parsed.headers, ['STN', 'Type']);
      expect(parsed.rows.single, ['D-1', 'सम्मन']);
    });
  });
}
