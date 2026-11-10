import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/local_database.dart';
import '../theme/app_theme.dart';

class ImportExportScreen extends StatefulWidget {
  const ImportExportScreen({super.key, this.initialModule = 'cases'});
  final String initialModule;
  @override
  State<ImportExportScreen> createState() => _ImportExportScreenState();
}

class _ImportExportScreenState extends State<ImportExportScreen> {
  static const _modules = <String, String>{
    'cases': 'सेशन कोर्ट',
    'dak_register': 'डाक रजिस्टर',
    'remand_register': 'रिमांड रजिस्टर',
    'address_book': 'Address Book',
  };
  static const _aliases = <String, List<String>>{
    'st_no': ['st no', 'st no.', 'st_no', 'stn', 'क्रमांक', 'क्रम', 'एसटी नंबर'],
    'fir_no': ['fir no', 'fir no.', 'मु0अ0स0', 'मु0अ0सं0', 'अपराध संख्या'],
    'sections': ['धारा', 'sections'],
    'accused_name': ['राज्य बनाम', 'बनाम', 'अभियुक्त', 'अभियुक्त का नाम', 'accused name'],
    'court_name': ['न्यायालय', 'कोर्ट', 'कोर्ट का नाम', 'court', 'court name'],
    'summoned_witnesses': ['तलब साक्षी', 'गवाह', 'summoned witnesses'],
    'next_hearing': ['तारीख पेशी', 'अगली पेशी', 'अगली तारीख पेशी', 'next hearing'],
    'previous_hearing': ['पिछली पेशी', 'previous hearing'],
    'status': ['status', 'स्थिति'],
    'summons_status': ['सम्मन की स्थिति', 'summons status'],
    'monitoring_type': ['type of moni', 'monitoring type'],
    'action_taken': ['कृत कार्यवाही', 'कार्यवाही', 'action taken'],
    'total_witnesses': ['कुल गवाह', 'total witnesses'],
    'fir_date': ['fir दिनांक', 'fir date'],
    'charge_sheet_date': ['आरोप पत्र प्रेषित', 'charge sheet date'],
    'cognizance_date': ['प्रसंज्ञान दिनांक', 'cognizance date'],
    'charge_framed_date': ['चार्ज फ्रेम', 'charge framed'],
    'station_received_date': ['थाने पर देने का दिनाँक', 'थाने पर लाने का दिनांक', 'थाना प्राप्ति दिनांक'],
    'dak_type': ['डाक का प्रकार', 'dak type', 'type'],
    'person_address': ['व्यक्ति का पता', 'पता', 'address'],
    'related_station': ['संबंधित थाना', 'थाना'],
    'hearing_date': ['पेशी दिनांक', 'तारीख़ पेशी', 'तारीख पेशी', 'hearing date'],
    'remarks': ['टिप्पणी', 'रिमार्क', 'रिमार्क्स', 'remarks'],
    'remand_date': ['रिमांड दिनांक', 'रिमांड date', 'remand date'],
    'investigating_officer': ['विवेचक', 'io', 'investigating officer'],
    'first_remand_date': ['प्रथम रिमांड दिनांक', 'first रिमांड डेट', 'first remand date'],
    'accused_details': ['अभियुक्त का विवरण', 'नाम पता अभियुक्त', 'accused details'],
    'name': ['नाम', 'name'],
    'mobile': ['मोबाइल', 'मोबाइल नंबर', 'mobile', 'phone'],
    'department': ['पद', 'विभाग', 'department'],
    'address': ['पता', 'पूरा पता', 'address'],
  };

  String _module = 'cases';
  List<String> _columns = [];
  Map<String, String> _columnLabels = {};
  List<String> _headers = [];
  List<List<String>> _sourceRows = [];
  List<int> _sourceRowNumbers = [];
  Map<int, String?> _mapping = {};
  String _sourceName = '';
  Excel? _workbook;
  List<String> _sheetNames = [];
  String? _selectedSheet;
  bool _busy = false;
  Map<String, int>? _result;
  List<Map<String, Object?>> _importErrors = [];
  Set<int> _duplicateRows = {};
  Map<int, String> _invalidRows = {};
  Set<int> _selectedRows = {};

  @override
  void initState() { super.initState(); _module = widget.initialModule; _loadColumns(); }

  Future<void> _loadColumns() async {
    final cols = await LocalDatabase.instance.importableColumns(_module);
    final fields = await LocalDatabase.instance.getFieldDefinitions(_module);
    final labels = <String, String>{for (final c in cols) c: c};
    for (final field in fields) {
      labels['custom:${field['id']}'] = '${field['label']} (Custom)';
    }
    if (!mounted) return;
    setState(() { _columns = cols; _columnLabels = labels; _headers = []; _sourceRows = []; _mapping = {}; _result = null; });
  }

  String _norm(String value) => value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9ऀ-ॿ]+'), '').trim();

  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['xlsx'], withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    if (file.bytes == null) {
      _message('फाइल पढ़ी नहीं जा सकी।');
      return;
    }
    try {
      final book = Excel.decodeBytes(file.bytes!);
      if (book.tables.isEmpty) throw const FormatException('शीट खाली है।');
      setState(() {
        _workbook = book;
        _sheetNames = book.tables.keys.toList();
        _selectedSheet = _sheetNames.first;
        _sourceName = file.name;
        _result = null;
      });
      await _readSelectedSheet();
    } catch (e) { _message('Excel फाइल नहीं पढ़ी गई: $e'); }
  }

  Future<void> _readSelectedSheet() async {
    final book = _workbook;
    final sheetName = _selectedSheet;
    if (book == null || sheetName == null || !book.tables.containsKey(sheetName)) return;
    final sheet = book.tables[sheetName]!;
    final rows = sheet.rows
        .map((r) => r.map((c) => c?.value?.toString() ?? '').toList())
        .toList();
    if (rows.length < 2) {
      _message('चुनी गई शीट में हेडर और कम-से-कम एक डेटा पंक्ति होनी चाहिए।');
      return;
    }
    final headers = rows.first;
    final data = <List<String>>[];
    final sourceRowNumbers = <int>[];
    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      if (!row.any((v) => v.trim().isNotEmpty)) continue;
      data.add(List.generate(headers.length, (i) => i < row.length ? row[i] : ''));
      sourceRowNumbers.add(rowIndex + 1);
    }
    final map = <int, String?>{};
    for (var i = 0; i < headers.length; i++) {
      final h = _norm(headers[i]);
      String? match;
      for (final col in _columns) {
        final names = <String>[col, ...(_aliases[col] ?? [])];
        if (names.any((a) => _norm(a) == h) && h.isNotEmpty) {
          match = col;
          break;
        }
      }
      map[i] = match;
    }
    if (!mounted) return;
    setState(() {
      _headers = headers;
      _sourceRows = data;
      _sourceRowNumbers = sourceRowNumbers;
      _mapping = map;
      _result = null;
      _duplicateRows = {};
      _invalidRows = {};
      _selectedRows = {};
    });
    await _analyseRows();
  }

  String _convertValue(String column, String value) {
    final v = value.trim();
    if (v.isEmpty) return '';
    if (column == 'total_witnesses') return int.tryParse(v)?.toString() ?? v;
    // Keep case/ST numbers as text; convert common Indian date formats to DD/MM/YYYY.
    final dateColumns = {'next_hearing','previous_hearing','fir_date','charge_sheet_date',
      'cognizance_date','charge_framed_date','station_received_date','hearing_date',
      'remand_date','first_remand_date'};
    if (dateColumns.contains(column)) {
      final m = RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{4})$').firstMatch(v);
      if (m != null) return '${m.group(1)!.padLeft(2,'0')}/${m.group(2)!.padLeft(2,'0')}/${m.group(3)}';
    }
    return v;
  }

  List<Map<String, Object?>> get _preview => _sourceRows.map((row) {
    final values = <String, Object?>{};
    for (var i = 0; i < _headers.length; i++) {
      final target = _mapping[i];
      if (target != null && target.isNotEmpty && target != '__ignore__') values[target] = _convertValue(target, i < row.length ? row[i] : '');
    }
    return values;
  }).toList();

  Future<void> _analyseRows() async {
    final current = await LocalDatabase.instance.exportRegisterRows(_module);
    String key(Map<String, Object?> row) {
      final fields = switch (_module) {
        'cases' => ['st_no'],
        'dak_register' => ['st_no', 'dak_type'],
        'remand_register' => ['fir_no', 'remand_date'],
        _ => ['mobile', 'name'],
      };
      final values = fields.map((f) => (row[f] ?? '').toString().trim().toLowerCase()).toList();
      return values.every((v) => v.isEmpty) ? '' : values.join('|');
    }
    final existing = current.map(key).where((v) => v.isNotEmpty).toSet();
    final seen = <String>{};
    final duplicates = <int>{};
    final invalid = <int, String>{};
    final values = _preview;
    for (var i = 0; i < values.length; i++) {
      final row = values[i];
      final identity = key(row);
      if (identity.isEmpty) invalid[i] = 'मुख्य पहचान वाला कॉलम खाली है';
      else if (existing.contains(identity) || !seen.add(identity)) duplicates.add(i);
      if (_module == 'cases' && (row['st_no'] ?? '').toString().trim().isEmpty) {
        invalid[i] = 'ST No. आवश्यक है';
      }
      if (_module == 'address_book' && (row['name'] ?? '').toString().trim().isEmpty) {
        invalid[i] = 'नाम आवश्यक है';
      }
      if (row.containsKey('total_witnesses') &&
          int.tryParse(row['total_witnesses'].toString()) == null) {
        invalid[i] = 'कुल गवाह संख्या गलत है';
      }
    }
    if (!mounted) return;
    setState(() {
      _duplicateRows = duplicates;
      _invalidRows = invalid;
      _selectedRows = {
        for (var i = 0; i < values.length; i++)
          if (!invalid.containsKey(i)) i,
      };
    });
  }

  Future<void> _import() async {
    final unmapped = <String>[
      for (var i = 0; i < _headers.length; i++)
        if (_headers[i].trim().isNotEmpty && _mapping[i] == null)
          _headers[i],
    ];
    if (unmapped.isNotEmpty) {
      _message('पहले इन कॉलम का मिलान करें या उन्हें स्पष्ट रूप से छोड़ने का निर्णय लें: ${unmapped.join(', ')}');
      return;
    }
    final allRows = _preview;
    final rows = [for (var i = 0; i < allRows.length; i++) if (_selectedRows.contains(i) && !_invalidRows.containsKey(i)) allRows[i]];
    if (rows.isEmpty) { _message('Import के लिए कोई वैध रिकॉर्ड चयनित नहीं है।'); return; }
    setState(() => _busy = true);
    try {
      final selectedSourceRows = [
        for (var i = 0; i < _sourceRows.length; i++)
          if (_selectedRows.contains(i) && !_invalidRows.containsKey(i))
            _sourceRowNumbers[i],
      ];
      final result = await LocalDatabase.instance.importRegisterRows(
        _module, rows, sourceName: '$_sourceName / ${_selectedSheet ?? ''}',
        sourceRowNumbers: selectedSourceRows,
      );
      final rowErrors = await LocalDatabase.instance.latestImportRowErrors(
        _module, '$_sourceName / ${_selectedSheet ?? ''}');
      if (!mounted) return;
      setState(() { _result = result; _importErrors = rowErrors; });
      _message('Import पूरा हुआ।');
    } catch (e) { _message('Import विफल: $e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _exportImportIssues() async {
    if (_importErrors.isEmpty) {
      _message('इस Import के लिए कोई समीक्षा पंक्ति नहीं है।');
      return;
    }
    try {
      final book = Excel.createExcel();
      final sheet = book['Import Review'];
      sheet.appendRow([
        TextCellValue('Excel Row'),
        TextCellValue('Outcome'),
        TextCellValue('Reason'),
        TextCellValue('Original Row Data'),
      ]);
      for (final issue in _importErrors) {
        sheet.appendRow([
          IntCellValue((issue['source_row'] as num?)?.toInt() ?? 0),
          TextCellValue((issue['outcome'] ?? '').toString()),
          TextCellValue((issue['reason'] ?? '').toString()),
          TextCellValue((issue['row_data'] ?? '').toString()),
        ]);
      }
      final bytes = book.encode();
      if (bytes == null) throw StateError('Review report Excel file was not created.');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/import_review_${DateTime.now().millisecondsSinceEpoch}.xlsx');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([XFile(file.path)], text: 'Import row review — ${_modules[_module]}');
    } catch (e) {
      _message('Review रिपोर्ट Export नहीं हुई: $e');
    }
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final rows = await LocalDatabase.instance.exportRegisterRows(_module);
      final book = Excel.createExcel();
      final sheet = book['Records'];
      final headers = rows.isEmpty ? _columns : rows.first.keys.toList();
      sheet.appendRow(headers.map((v) => TextCellValue(v)).toList());
      for (final row in rows) {
        sheet.appendRow(headers.map((h) => TextCellValue((row[h] ?? '').toString())).toList());
      }
      final bytes = book.encode();
      if (bytes == null) throw StateError('Excel फाइल नहीं बनी।');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${_module}_export_${DateTime.now().millisecondsSinceEpoch}.xlsx');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([XFile(file.path)], text: '${_modules[_module]} — Excel Export');
    } catch (e) { _message('Export विफल: $e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Excel Import / Export')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Container(padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppTheme.navy, borderRadius: BorderRadius.circular(18)),
        child: const Text('Excel डेटा पहले Preview में देखें। कॉलम का मिलान जाँचें, फिर Import करें। पुराने रिकॉर्ड अपने-आप overwrite नहीं होंगे।',
          style: TextStyle(color: Colors.white, height: 1.5))),
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(initialValue: _module, decoration: const InputDecoration(labelText: 'मॉड्यूल'),
        items: _modules.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
        onChanged: _busy ? null : (v) { if (v != null) { setState(() => _module = v); _loadColumns(); } }),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : _pickFile,
          icon: const Icon(Icons.upload_file), label: const Text('Excel चुनें'))),
        const SizedBox(width: 10),
        Expanded(child: FilledButton.icon(onPressed: _busy ? null : _export,
          icon: const Icon(Icons.download), label: const Text('Export Excel'))),
      ]),
      if (_sourceName.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('फाइल: $_sourceName', style: const TextStyle(fontWeight: FontWeight.w700)),
        if (_sheetNames.length > 1) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _selectedSheet,
            decoration: const InputDecoration(labelText: 'Excel शीट चुनें'),
            items: _sheetNames.map((name) =>
              DropdownMenuItem(value: name, child: Text(name))).toList(),
            onChanged: _busy ? null : (value) async {
              if (value == null) return;
              setState(() => _selectedSheet = value);
              await _readSelectedSheet();
            },
          ),
        ] else if (_selectedSheet != null)
          Text('शीट: $_selectedSheet', style: Theme.of(context).textTheme.bodySmall),
        Text('${_sourceRows.length} डेटा पंक्तियाँ • शीट: ${_selectedSheet ?? '—'}',
          style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 10),
        const Text('कॉलम मिलान', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ...List.generate(_headers.length, (i) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            Expanded(flex: 5, child: Text(_headers[i].isEmpty ? '(खाली हेडर)' : _headers[i], maxLines: 2)),
            const Icon(Icons.arrow_forward, size: 16),
            const SizedBox(width: 8),
            Expanded(flex: 6, child: DropdownButtonFormField<String>(
              initialValue: _mapping[i], isExpanded: true, decoration: const InputDecoration(isDense: true),
              items: [const DropdownMenuItem<String>(value: '__ignore__', child: Text('जानबूझकर छोड़ें')),
                ..._columns.map((c) => DropdownMenuItem(value: c, child: Text(_columnLabels[c] ?? c, overflow: TextOverflow.ellipsis)))],
              onChanged: (v) async { setState(() => _mapping[i] = v); await _analyseRows(); },
            )),
          ]),
        )),
        const SizedBox(height: 14),
        Text('Preview • चयनित ${_selectedRows.length} / ${_sourceRows.length}', style: const TextStyle(fontWeight: FontWeight.w800)),
        Text('डुप्लीकेट: ${_duplicateRows.length} • अमान्य: ${_invalidRows.length}',
          style: const TextStyle(fontSize: 12, color: Colors.deepOrange)),
        ...List.generate(_sourceRows.length > 30 ? 30 : _sourceRows.length, (i) {
          final issue = _invalidRows[i] ?? (_duplicateRows.contains(i) ? 'डुप्लीकेट रिकॉर्ड' : '');
          final row = _preview[i];
          return CheckboxListTile(
            dense: true, contentPadding: EdgeInsets.zero,
            value: _selectedRows.contains(i),
            onChanged: _invalidRows.containsKey(i) ? null : (v) => setState(() {
              if (v == true) { _selectedRows.add(i); } else { _selectedRows.remove(i); }
            }),
            title: Text('पंक्ति ${i < _sourceRowNumbers.length ? _sourceRowNumbers[i] : i + 2} • ${row.values.take(3).where((v) => v.toString().isNotEmpty).join(' / ')}',
              maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: issue.isEmpty ? null : Text(issue, style: const TextStyle(color: Colors.deepOrange)),
          );
        }),
        if (_sourceRows.length > 30) const Text('पहली 30 पंक्तियाँ दिखाई गई हैं; अन्य वैध पंक्तियाँ भी चयनित हैं।'),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _busy || _selectedRows.isEmpty ? null : _import,
          icon: const Icon(Icons.playlist_add_check), label: Text(_busy ? 'प्रक्रिया जारी…' : '${_selectedRows.length} चयनित रिकॉर्ड Import करें')),
      ],
      if (_result != null) ...[
        const SizedBox(height: 14),
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Import रिपोर्ट', style: TextStyle(fontWeight: FontWeight.w800)),
          Text('कुल: ${_result!['total']}'),
          Text('सफल: ${_result!['imported']}'),
          Text('Duplicate / खाली छोड़े: ${_result!['skipped']}'),
          Text('त्रुटियाँ: ${_result!['errors']}'),
          Text('मैनुअल समीक्षा / Duplicate / छोड़े गए: ${_importErrors.length}'),
          if (_importErrors.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _exportImportIssues,
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('समीक्षा रिपोर्ट Excel में Export करें'),
              ),
            ),
          if (_importErrors.isNotEmpty) ...[
            const Divider(),
            const Text('पंक्ति-वार समीक्षा रिपोर्ट', style: TextStyle(fontWeight: FontWeight.w700)),
            ..._importErrors.take(50).map((issue) => Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Excel पंक्ति ${issue['source_row']} • ${issue['outcome']}\n${issue['reason']}',
                style: const TextStyle(fontSize: 12),
              ),
            )),
            if (_importErrors.length > 50)
              Text('अन्य ${_importErrors.length - 50} मुद्दे भी रिपोर्ट में सुरक्षित हैं।'),
          ],
        ]))),
      ],
      const SizedBox(height: 20),
      const Text('नोट: Google Sheets से पहले Excel (.xlsx) डाउनलोड करें। ST NO और FIR नंबर को टेक्स्ट के रूप में सुरक्षित रखा जाता है।',
        style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.5)),
    ]),
  );
}
