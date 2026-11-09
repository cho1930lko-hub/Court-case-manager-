import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../data/local_database.dart';

class CasesScreen extends StatefulWidget {
  const CasesScreen({super.key});

  @override
  State<CasesScreen> createState() => _CasesScreenState();
}

class _CasesScreenState extends State<CasesScreen> {
  final _search = TextEditingController();
  List<Map<String, Object?>> _cases = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(_load);
  }

  @override
  void dispose() {
    _search.removeListener(_load);
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final rows = await LocalDatabase.instance.searchCases(_search.text);
    if (!mounted) return;
    setState(() {
      _cases = rows;
      _loading = false;
    });
  }

  Future<void> _editCase([Map<String, Object?>? row]) async {
    final result = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CaseForm(initial: row),
    );
    if (result == null) return;
    final id = (row?['id'] ?? const Uuid().v4()).toString();
    try {
      await LocalDatabase.instance.saveCase({...result, 'id': id}, id: row?['id']?.toString());
      await LocalDatabase.instance.logAction(
        row == null ? 'CASE_CREATED' : 'CASE_UPDATED',
        'SESSION_COURT',
        id,
        'ST NO: ${result['st_no']}',
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(row == null ? 'मुकदमा सेव हो गया।' : 'मुकदमा अपडेट हो गया।')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('सेव नहीं हुआ: $e')));
      }
    }
  }

  Future<void> _archive(Map<String, Object?> row) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('रिकॉर्ड आर्काइव करें?'),
        content: const Text('रिकॉर्ड हटेगा नहीं; केवल मुख्य सूची से छिपेगा।'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('रद्द')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('आर्काइव')),
        ],
      ),
    );
    if (yes != true) return;
    final id = row['id'].toString();
    await LocalDatabase.instance.archiveCase(id);
    await LocalDatabase.instance.logAction('CASE_ARCHIVED', 'SESSION_COURT', id, 'Soft archive');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('सेशन कोर्ट')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editCase(),
        icon: const Icon(Icons.add),
        label: const Text('नया मुकदमा'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'ST NO, मु0अ0सं0, नाम या धारा खोजें',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: _search.clear,
                  icon: const Icon(Icons.close),
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _cases.isEmpty
                    ? const Center(child: Text('अभी कोई मुकदमा नहीं है। + नया मुकदमा से शुरुआत करें।'))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                          itemCount: _cases.length,
                          itemBuilder: (context, index) {
                            final row = _cases[index];
                            return Card(
                              child: ListTile(
                                onTap: () => _editCase(row),
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFFEAF0FF),
                                  child: Text('${row['st_no'] ?? '-'}', style: const TextStyle(fontSize: 11)),
                                ),
                                title: Text('राज्य बनाम ${row['accused_name'] ?? ''}',
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text(
                                  'मु0अ0सं0: ${row['fir_no'] ?? '-'}  •  धारा: ${row['sections'] ?? '-'}\n'
                                  '${row['court_name'] ?? ''}  •  अगली पेशी: ${row['next_hearing'] ?? '-'}',
                                ),
                                isThreeLine: true,
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'edit') _editCase(row);
                                    if (value == 'archive') _archive(row);
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: 'edit', child: Text('संपादित करें')),
                                    PopupMenuItem(value: 'archive', child: Text('आर्काइव')),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _CaseForm extends StatefulWidget {
  const _CaseForm({this.initial});
  final Map<String, Object?>? initial;

  @override
  State<_CaseForm> createState() => _CaseFormState();
}

class _CaseFormState extends State<_CaseForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController stNo;
  late final TextEditingController firNo;
  late final TextEditingController sections;
  late final TextEditingController accused;
  late final TextEditingController court;
  late final TextEditingController witnesses;
  late final TextEditingController nextHearing;
  late final TextEditingController action;
  String status = 'साक्ष्य';

  @override
  void initState() {
    super.initState();
    final r = widget.initial ?? {};
    stNo = TextEditingController(text: '${r['st_no'] ?? ''}');
    firNo = TextEditingController(text: '${r['fir_no'] ?? ''}');
    sections = TextEditingController(text: '${r['sections'] ?? ''}');
    accused = TextEditingController(text: '${r['accused_name'] ?? ''}');
    court = TextEditingController(text: '${r['court_name'] ?? ''}');
    witnesses = TextEditingController(text: '${r['summoned_witnesses'] ?? ''}');
    nextHearing = TextEditingController(text: '${r['next_hearing'] ?? ''}');
    action = TextEditingController(text: '${r['action_taken'] ?? ''}');
    status = (r['status'] ?? 'साक्ष्य').toString();
  }

  @override
  void dispose() {
    for (final c in [stNo, firNo, sections, accused, court, witnesses, nextHearing, action]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(String label, TextEditingController c, {bool required = false, int lines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: c,
          maxLines: lines,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'यह विवरण आवश्यक है' : null : null,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 18, 18, MediaQuery.of(context).viewInsets.bottom + 18),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.initial == null ? 'नया मुकदमा जोड़ें' : 'मुकदमा अपडेट करें',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 14),
              _field('ST NO', stNo, required: true),
              _field('मु0अ0सं0', firNo),
              _field('धारा', sections),
              _field('बनाम / अभियुक्त का नाम', accused, required: true),
              _field('न्यायालय', court),
              _field('तलब साक्षी', witnesses),
              _field('अगली तारीख पेशी (DD/MM/YYYY)', nextHearing),
              DropdownButtonFormField<String>(
                value: status,
                decoration: const InputDecoration(labelText: 'मुकदमे की स्थिति', border: OutlineInputBorder()),
                items: const ['साक्ष्य','हाजिरी','बहस','313 सीआरपीसी','सफाई साक्ष्य','जजमेंट','सजा','दोष मुक्त','अभियुक्त NBW']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                onChanged: (v) => setState(() => status = v ?? status),
              ),
              const SizedBox(height: 10),
              _field('कृत कार्यवाही', action, lines: 3),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  if (!_formKey.currentState!.validate()) return;
                  Navigator.pop(context, {
                    'st_no': stNo.text.trim(),
                    'fir_no': firNo.text.trim(),
                    'sections': sections.text.trim(),
                    'accused_name': accused.text.trim(),
                    'court_name': court.text.trim(),
                    'summoned_witnesses': witnesses.text.trim(),
                    'next_hearing': nextHearing.text.trim(),
                    'status': status,
                    'action_taken': action.text.trim(),
                  });
                },
                icon: const Icon(Icons.save),
                label: const Text('सेव करें'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
