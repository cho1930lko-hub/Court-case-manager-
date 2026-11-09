import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../data/local_database.dart';
import '../theme/app_theme.dart';

class EvidenceScreen extends StatefulWidget {
  const EvidenceScreen({super.key});

  @override
  State<EvidenceScreen> createState() => _EvidenceScreenState();
}

class _EvidenceScreenState extends State<EvidenceScreen> {
  List<Map<String, Object?>> _cases = [];
  List<Map<String, Object?>> _items = [];
  String? _caseId;
  bool _loading = true;
  bool _saving = false;
  String _filter = 'सभी';

  static const _types = ['सभी', 'बरामदगी', 'भौतिक साक्ष्य', 'दस्तावेज', 'इलेक्ट्रॉनिक साक्ष्य', 'अन्य'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final cases = await LocalDatabase.instance.searchCases('');
      final selected = _caseId ?? (cases.isNotEmpty ? cases.first['id'].toString() : null);
      final rows = await LocalDatabase.instance.evidenceItems(caseId: selected);
      if (!mounted) return;
      setState(() {
        _cases = cases;
        _caseId = selected;
        _items = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('साक्ष्य रिकॉर्ड लोड नहीं हुए: $e')),
      );
    }
  }

  List<Map<String, Object?>> get _visible => _filter == 'सभी'
      ? _items
      : _items.where((e) => e['item_type'] == _filter).toList();

  Future<String?> _copyAttachment(String caseId) async {
    final result = await FilePicker.platform.pickFiles(withData: false);
    if (result == null || result.files.single.path == null) return null;
    final source = File(result.files.single.path!);
    final root = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(root.path, 'evidence', caseId));
    await folder.create(recursive: true);
    final target = p.join(folder.path, '${const Uuid().v4()}_${p.basename(source.path)}');
    await source.copy(target);
    return target;
  }

  Future<void> _edit([Map<String, Object?>? item]) async {
    if (_caseId == null || _saving) return;
    final result = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.canvas,
      builder: (_) => _EvidenceForm(
        cases: _cases,
        initial: item,
        defaultCaseId: _caseId!,
        onAttach: _copyAttachment,
      ),
    );
    if (result == null) return;
    setState(() => _saving = true);
    try {
      final id = (item?['id'] ?? const Uuid().v4()).toString();
      await LocalDatabase.instance.saveEvidence(result, id: item?['id']?.toString());
      await LocalDatabase.instance.logAction(
        item == null ? 'EVIDENCE_CREATED' : 'EVIDENCE_UPDATED',
        'EVIDENCE',
        id,
        result['description']?.toString() ?? '',
      );
      _caseId = result['case_id']?.toString() ?? _caseId;
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('साक्ष्य सेव नहीं हुआ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(Map<String, Object?> item) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('साक्ष्य रिकॉर्ड हटाएँ?'),
        content: const Text('यह प्रविष्टि हटेगी। संलग्न मूल फाइल अपने स्थान पर रहेगी।'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('रद्द')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('हटाएँ')),
        ],
      ),
    );
    if (yes != true) return;
    await LocalDatabase.instance.deleteEvidence(item['id'].toString());
    await LocalDatabase.instance.logAction(
      'EVIDENCE_RECORD_DELETED',
      'EVIDENCE',
      item['id'].toString(),
      item['description']?.toString() ?? '',
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    return Scaffold(
      appBar: AppBar(title: const Text('Evidence एवं Exhibit Manager')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _cases.isEmpty ? null : () => _edit(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('साक्ष्य जोड़ें'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _cases.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Text('पहले सेशन कोर्ट में मुकदमा दर्ज करें, फिर उससे संबंधित साक्ष्य जोड़ें।',
                        textAlign: TextAlign.center),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: DropdownButtonFormField<String>(
                        initialValue: _caseId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'मुकदमा चुनें',
                          prefixIcon: Icon(Icons.gavel_rounded),
                        ),
                        items: _cases.map((c) {
                          final id = c['id'].toString();
                          return DropdownMenuItem(
                            value: id,
                            child: Text(
                              'ST No. ${c['st_no'] ?? ''}  •  ${c['accused_name'] ?? ''}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) async {
                          if (value == null) return;
                          setState(() {
                            _caseId = value;
                            _loading = true;
                          });
                          await _load();
                        },
                      ),
                    ),
                    SizedBox(
                      height: 46,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        scrollDirection: Axis.horizontal,
                        itemCount: _types.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final type = _types[index];
                          return ChoiceChip(
                            label: Text(type),
                            selected: _filter == type,
                            onSelected: (_) => setState(() => _filter = type),
                          );
                        },
                      ),
                    ),
                    Expanded(
                      child: rows.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(28),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.inventory_2_outlined, size: 46, color: AppTheme.muted),
                                    const SizedBox(height: 12),
                                    Text('इस मुकदमे में अभी कोई साक्ष्य प्रविष्टि नहीं है',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context).textTheme.titleMedium),
                                    const SizedBox(height: 6),
                                    const Text('बरामदगी, माल-मुकदमा, Exhibit और संलग्न फाइल का विवरण दर्ज करें।',
                                        textAlign: TextAlign.center),
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
                              itemCount: rows.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final e = rows[index];
                                final attached = (e['local_path'] ?? '').toString().isNotEmpty;
                                final produced = e['produced_in_court'] == 1;
                                return Card(
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                    leading: CircleAvatar(
                                      backgroundColor: AppTheme.teal.withValues(alpha: .10),
                                      child: const Icon(Icons.inventory_2_outlined, color: AppTheme.teal),
                                    ),
                                    title: Text(e['description']?.toString() ?? '',
                                        style: const TextStyle(fontWeight: FontWeight.w700)),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 5),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('${e['item_type']}  •  ${(e['seizure_date'] ?? '').toString()}'),
                                          if ((e['exhibit_no'] ?? '').toString().isNotEmpty)
                                            Text('Exhibit: ${e['exhibit_no']}'),
                                          if ((e['malkhana_entry'] ?? '').toString().isNotEmpty)
                                            Text('मालखाना: ${e['malkhana_entry']}'),
                                          Text(produced ? 'न्यायालय में प्रस्तुत' : 'न्यायालय में प्रस्तुत नहीं'),
                                          if (attached) const Text('फाइल संलग्न है'),
                                        ],
                                      ),
                                    ),
                                    trailing: PopupMenuButton<String>(
                                      onSelected: (value) {
                                        if (value == 'edit') _edit(e);
                                        if (value == 'delete') _delete(e);
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(value: 'edit', child: Text('संशोधित करें')),
                                        PopupMenuItem(value: 'delete', child: Text('रिकॉर्ड हटाएँ')),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}

class _EvidenceForm extends StatefulWidget {
  const _EvidenceForm({
    required this.cases,
    required this.initial,
    required this.defaultCaseId,
    required this.onAttach,
  });

  final List<Map<String, Object?>> cases;
  final Map<String, Object?>? initial;
  final String defaultCaseId;
  final Future<String?> Function(String caseId) onAttach;

  @override
  State<_EvidenceForm> createState() => _EvidenceFormState();
}

class _EvidenceFormState extends State<_EvidenceForm> {
  final _formKey = GlobalKey<FormState>();
  late String _caseId;
  late String _type;
  late bool _produced;
  String _path = '';
  final _description = TextEditingController();
  final _date = TextEditingController();
  final _source = TextEditingController();
  final _malkhana = TextEditingController();
  final _seal = TextEditingController();
  final _exhibit = TextEditingController();
  final _remarks = TextEditingController();

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _caseId = (e?['case_id'] ?? widget.defaultCaseId).toString();
    _type = (e?['item_type'] ?? 'बरामदगी').toString();
    _produced = e?['produced_in_court'] == 1;
    _path = (e?['local_path'] ?? '').toString();
    _description.text = (e?['description'] ?? '').toString();
    _date.text = (e?['seizure_date'] ?? '').toString();
    _source.text = (e?['seized_from'] ?? '').toString();
    _malkhana.text = (e?['malkhana_entry'] ?? '').toString();
    _seal.text = (e?['seal_details'] ?? '').toString();
    _exhibit.text = (e?['exhibit_no'] ?? '').toString();
    _remarks.text = (e?['remarks'] ?? '').toString();
  }

  @override
  void dispose() {
    _description.dispose();
    _date.dispose();
    _source.dispose();
    _malkhana.dispose();
    _seal.dispose();
    _exhibit.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Widget _field(TextEditingController controller, String label, {int lines = 1, String? hint}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: controller,
          maxLines: lines,
          decoration: InputDecoration(labelText: label, hintText: hint),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.initial == null ? 'नया साक्ष्य / Exhibit' : 'साक्ष्य विवरण संशोधित करें',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _caseId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'संबंधित मुकदमा'),
                items: widget.cases.map((c) => DropdownMenuItem(
                  value: c['id'].toString(),
                  child: Text('ST No. ${c['st_no']} • ${c['accused_name']}', overflow: TextOverflow.ellipsis),
                )).toList(),
                onChanged: (v) => setState(() => _caseId = v ?? _caseId),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'साक्ष्य का प्रकार'),
                items: const ['बरामदगी', 'भौतिक साक्ष्य', 'दस्तावेज', 'इलेक्ट्रॉनिक साक्ष्य', 'अन्य']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
              const SizedBox(height: 10),
              _field(_description, 'वस्तु / साक्ष्य का विवरण *'),
              _field(_date, 'बरामदगी / जब्ती की तारीख', hint: 'YYYY-MM-DD'),
              _field(_source, 'कहाँ से / किसके कब्जे से प्राप्त'),
              _field(_malkhana, 'मालखाना जमा संख्या / विवरण'),
              _field(_seal, 'सील / पैकेट का विवरण'),
              _field(_exhibit, 'न्यायालय Exhibit संख्या'),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _produced,
                onChanged: (v) => setState(() => _produced = v ?? false),
                title: const Text('न्यायालय में प्रस्तुत किया जा चुका है'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              _field(_remarks, 'अन्य टिप्पणी', lines: 2),
              OutlinedButton.icon(
                onPressed: () async {
                  final path = await widget.onAttach(_caseId);
                  if (path != null && mounted) setState(() => _path = path);
                },
                icon: const Icon(Icons.attach_file_rounded),
                label: Text(_path.isEmpty ? 'फोटो / दस्तावेज संलग्न करें' : 'संलग्न फाइल बदलें'),
              ),
              if (_path.isNotEmpty)
                Text(p.basename(_path), style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () {
                  if (!_formKey.currentState!.validate()) return;
                  if (_description.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('साक्ष्य का विवरण आवश्यक है।')),
                    );
                    return;
                  }
                  Navigator.pop(context, {
                    'case_id': _caseId,
                    'item_type': _type,
                    'description': _description.text.trim(),
                    'seizure_date': _date.text.trim(),
                    'seized_from': _source.text.trim(),
                    'malkhana_entry': _malkhana.text.trim(),
                    'seal_details': _seal.text.trim(),
                    'exhibit_no': _exhibit.text.trim(),
                    'produced_in_court': _produced ? 1 : 0,
                    'local_path': _path,
                    'remarks': _remarks.text.trim(),
                  });
                },
                child: const Text('साक्ष्य सेव करें'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
