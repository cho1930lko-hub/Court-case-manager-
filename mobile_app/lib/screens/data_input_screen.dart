import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/local_database.dart';
import '../services/data_management_service.dart';

class DataInputScreen extends StatefulWidget {
  const DataInputScreen({super.key, this.initialModule = 'cases'});
  final String initialModule;
  @override
  State<DataInputScreen> createState() => _DataInputScreenState();
}

class _DataInputScreenState extends State<DataInputScreen> {
  final _service = DataManagementService.instance;
  late String _module;
  List<List<String>>? _source;
  ImportPreview? _preview;
  String _fileName = '';
  Map<String, String> _mapping = {};
  Set<int> _selected = {};
  bool _busy = false;
  String? _notice;

  @override
  void initState() { super.initState(); _module = widget.initialModule; }

  Future<void> _choose() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['xlsx', 'xls'], withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    setState(() { _busy = true; _notice = null; });
    try {
      final source = _service.readWorkbook(result.files.single.bytes!);
      final mapping = _service.autoMatch(_module, source.first);
      final preview = await _service.preview(_module, source, mapping);
      setState(() {
        _source = source; _fileName = result.files.single.name;
        _mapping = mapping; _preview = preview;
        _selected = {for (var i=0; i<preview.rows.length; i++)
          if (!preview.duplicates.contains(i+2) && !preview.invalid.containsKey(i+2)) i+2};
      });
    } catch (e) { setState(() => _notice = 'फाइल पढ़ने में समस्या: $e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _changeMapping(String field, String? header) async {
    if (header == null || _source == null) return;
    final next = {..._mapping, field: header};
    final p = await _service.preview(_module, _source!, next);
    setState(() { _mapping = next; _preview = p; });
  }

  Future<void> _import() async {
    final preview = _preview;
    if (preview == null || _selected.isEmpty) return;
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Import की पुष्टि'),
      content: Text('${_selected.length} रिकॉर्ड जोड़े जाएँगे। मौजूदा रिकॉर्ड overwrite नहीं होंगे।'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('रद्द')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Import करें')),
      ],
    ));
    if (yes != true) return;
    setState(() => _busy = true);
    try {
      final result = await _service.importRows(_module, _fileName, preview, _selected);
      setState(() {
        _notice = 'Import पूरा: ${result['imported']} जोड़े, ${result['skipped']} छोड़े, ${result['errors']} त्रुटियाँ।';
        _source = null; _preview = null; _mapping = {}; _selected = {};
      });
    } catch (e) { setState(() => _notice = 'Import विफल: $e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final rows = await LocalDatabase.instance.exportRegisterRows(_module);
      if (rows.isEmpty) { setState(() => _notice = 'Export के लिए कोई रिकॉर्ड नहीं है।'); return; }
      final headers = rows.first.keys.toList();
      String q(Object? value) => '"${(value ?? '').toString().replaceAll('"', '""')}"';
      final csv = '\uFEFF${[headers.map(q).join(','), ...rows.map((r) => headers.map((h) => q(r[h])).join(','))].join('\\r\\n')}';
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${_module}_export.csv');
      await file.writeAsString(csv, flush: true);
      await Share.shareXFiles([XFile(file.path)], text: '${DataManagementService.modules[_module]} Export');
    } catch (e) { setState(() => _notice = 'Export में समस्या: $e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(title: const Text('Data Input Center')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('रजिस्टर चुनें', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(value: _module,
              items: DataManagementService.modules.entries.map((e) =>
                DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
              onChanged: _busy ? null : (v) => setState(() { _module = v ?? 'cases'; _source = null; _preview = null; _mapping = {}; })),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(onPressed: _busy ? null : _choose, icon: const Icon(Icons.upload_file), label: const Text('Excel Import')),
              OutlinedButton.icon(onPressed: _busy ? null : _export, icon: const Icon(Icons.ios_share), label: const Text('Export CSV')),
            ]),
            const SizedBox(height: 8),
            const Text('Google Sheets से पहले File → Download → Microsoft Excel (.xlsx) चुनें। ऐप ऑफलाइन Import करेगा।',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ))),
        if (_busy) const LinearProgressIndicator(),
        if (_notice != null) Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(_notice!))),
        if (preview != null) ...[
          Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('कॉलम मिलान • $_fileName', style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${preview.rows.length} पंक्तियाँ • ${_mapping.length} कॉलम स्वतः पहचाने गए'),
              const Divider(),
              ..._mapping.entries.map((e) => Row(children: [
                Expanded(flex: 2, child: Text(e.key, style: const TextStyle(fontSize: 12))),
                const Icon(Icons.arrow_forward, size: 16),
                Expanded(flex: 3, child: DropdownButton<String>(isExpanded: true, value: e.value,
                  items: preview.headers.map((h) => DropdownMenuItem(value: h, child: Text(h, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) => _changeMapping(e.key, v))),
              ])),
              if (_mapping.isEmpty) const Text('कॉलम नहीं मिले। Excel हेडर जाँचें।'),
            ],
          ))),
          Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('रिकॉर्ड Preview • चयनित ${_selected.length} / ${preview.rows.length}'),
              Text('डुप्लीकेट ${preview.duplicates.length} • अमान्य ${preview.invalid.length}',
                style: const TextStyle(color: Colors.deepOrange, fontSize: 12)),
              ...List.generate(preview.rows.length > 30 ? 30 : preview.rows.length, (i) {
                final rowNo = i + 2;
                final issue = preview.invalid[rowNo] ?? (preview.duplicates.contains(rowNo) ? 'डुप्लीकेट' : '');
                return CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero,
                  value: _selected.contains(rowNo), onChanged: issue.isNotEmpty ? null : (v) =>
                    setState(() { if (v == true) { _selected.add(rowNo); } else { _selected.remove(rowNo); } }),
                  title: Text('पंक्ति $rowNo • ${preview.rows[i].take(3).where((v) => v.isNotEmpty).join(' / ')}',
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: issue.isEmpty ? null : Text(issue, style: const TextStyle(color: Colors.deepOrange)));
              }),
              if (preview.rows.length > 30) const Text('पहली 30 पंक्तियाँ दिखाई गई हैं; अन्य चयनित पंक्तियाँ भी Import होंगी।'),
              const SizedBox(height: 8),
              FilledButton.icon(onPressed: _busy || _selected.isEmpty ? null : _import,
                icon: const Icon(Icons.check_circle), label: Text('${_selected.length} रिकॉर्ड Import करें')),
            ],
          ))),
        ],
        const Card(child: Padding(padding: EdgeInsets.all(14), child: Text(
          'सुरक्षा: Import मौजूदा रिकॉर्ड को अपडेट नहीं करता। डुप्लीकेट छोड़े जाते हैं। सभी नए रिकॉर्ड और Import का Audit Log दर्ज होता है। ST No. को टेक्स्ट के रूप में सुरक्षित रखा जाता है।',
          style: TextStyle(fontSize: 12, height: 1.5)))),
      ]),
    );
  }
}
