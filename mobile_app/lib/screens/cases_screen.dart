import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/local_database.dart';
import '../theme/app_theme.dart';
import 'data_input_screen.dart';

class CasesScreen extends StatefulWidget {
  const CasesScreen({super.key});

  @override
  State<CasesScreen> createState() => _CasesScreenState();
}

class _CasesScreenState extends State<CasesScreen> {
  final _search = TextEditingController();
  List<Map<String, Object?>> _cases = [];
  bool _loading = true;
  String _filter = 'सभी';

  List<Map<String, Object?>> get _visibleCases {
    final rows = _cases.where((row) {
      final status = (row['status'] ?? 'साक्ष्य').toString();
      switch (_filter) {
        case 'आगामी पेशी':
          final date = _parseHearingDate(row['next_hearing']?.toString() ?? '');
          return date != null && !date.isBefore(DateUtils.dateOnly(DateTime.now()));
        case 'NBW': return status.contains('NBW');
        case 'बहस': return status == 'बहस';
        case 'साक्ष्य': return status == 'साक्ष्य' || status == 'सफाई साक्ष्य';
        case 'अन्य': return !['NBW', 'बहस', 'साक्ष्य', 'सफाई साक्ष्य'].any((v) => status.contains(v));
        default: return true;
      }
    }).toList();
    if (_filter == 'आगामी पेशी') {
      rows.sort((a, b) {
        final da = _parseHearingDate(a['next_hearing']?.toString() ?? '') ?? DateTime(9999);
        final db = _parseHearingDate(b['next_hearing']?.toString() ?? '') ?? DateTime(9999);
        return da.compareTo(db);
      });
    }
    return rows;
  }

  DateTime? _parseHearingDate(String value) {
    final parts = value.trim().split('/');
    if (parts.length != 3) return DateTime.tryParse(value.trim());
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    final date = DateTime(year, month, day);
    if (date.day != day || date.month != month || date.year != year) return null;
    return DateUtils.dateOnly(date);
  }

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
      backgroundColor: AppTheme.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _CaseForm(initial: row),
    );
    if (result == null) return;
    final id = (row?['id'] ?? const Uuid().v4()).toString();
    try {
      await LocalDatabase.instance.saveWithAudit(
        table: 'cases', values: result, recordId: id, isNew: row == null,
        action: row == null ? 'CASE_CREATED' : 'CASE_UPDATED',
        module: 'SESSION_COURT', details: 'ST NO: ${result['st_no']}',
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
    await LocalDatabase.instance.archiveCaseWithAudit(id);
    await _load();
  }

  Color _statusColor(String value) {
    if (value.contains('NBW')) return const Color(0xFFB54735);
    if (value == 'जजमेंट' || value == 'सजा' || value == 'दोष मुक्त') return AppTheme.teal;
    if (value == 'बहस') return const Color(0xFF8A641D);
    return AppTheme.blue;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('सेशन कोर्ट'),
        actions: [
          IconButton(tooltip: 'Excel Import / Export', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImportExportScreen(initialModule: 'cases'))), icon: const Icon(Icons.import_export_rounded)),
          IconButton(tooltip: 'रीफ्रेश', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editCase(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('नया मुकदमा'),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
            decoration: const BoxDecoration(
              color: AppTheme.navy,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('मुकदमा प्रबंधन', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                Text('${_visibleCases.length} / ${_cases.length} रिकॉर्ड', style: const TextStyle(color: Color(0xFFD4DEED), fontSize: 13)),
                const SizedBox(height: 16),
                TextField(
                  controller: _search,
                  style: const TextStyle(color: AppTheme.ink),
                  decoration: InputDecoration(
                    hintText: 'ST NO, मु0अ0सं0, नाम या धारा खोजें',
                    prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.muted),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(onPressed: _search.clear, icon: const Icon(Icons.close_rounded)),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              children: [
                for (final filter in ['सभी', 'आगामी पेशी', 'NBW', 'बहस', 'साक्ष्य', 'अन्य'])
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: ChoiceChip(
                      label: Text(filter),
                      selected: _filter == filter,
                      onSelected: (_) => setState(() => _filter = filter),
                      showCheckmark: false,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _visibleCases.isEmpty
                    ? _EmptyCases(searching: _search.text.isNotEmpty || _filter != 'सभी', onAdd: () => _editCase(), onClear: () { _search.clear(); setState(() => _filter = 'सभी'); })
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                          itemCount: _visibleCases.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 11),
                          itemBuilder: (context, index) {
                            final row = _visibleCases[index];
                            final status = (row['status'] ?? 'साक्ष्य').toString();
                            return Card(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () => _editCase(row),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(15, 14, 8, 14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            constraints: const BoxConstraints(minWidth: 58),
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                                            decoration: BoxDecoration(color: const Color(0xFFEAF0FA), borderRadius: BorderRadius.circular(12)),
                                            child: Column(
                                              children: [
                                                const Text('ST NO', style: TextStyle(fontSize: 9, color: AppTheme.muted, fontWeight: FontWeight.w700)),
                                                Text('${row['st_no'] ?? '-'}', style: const TextStyle(fontSize: 15, color: AppTheme.navy, fontWeight: FontWeight.w800)),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text('राज्य बनाम ${row['accused_name'] ?? 'नाम उपलब्ध नहीं'}',
                                                  maxLines: 2, overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.ink)),
                                                const SizedBox(height: 5),
                                                Text('मु0अ0सं0: ${row['fir_no'] ?? '-'}  •  धारा: ${row['sections'] ?? '-'}',
                                                  maxLines: 2, overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
                                              ],
                                            ),
                                          ),
                                          PopupMenuButton<String>(
                                            tooltip: 'अन्य विकल्प',
                                            onSelected: (value) {
                                              if (value == 'edit') _editCase(row);
                                              if (value == 'archive') _archive(row);
                                            },
                                            itemBuilder: (_) => const [
                                              PopupMenuItem(value: 'edit', child: ListTile(dense: true, leading: Icon(Icons.edit_outlined), title: Text('संपादित करें'))),
                                              PopupMenuItem(value: 'archive', child: ListTile(dense: true, leading: Icon(Icons.archive_outlined), title: Text('आर्काइव'))),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
                                      Row(
                                        children: [
                                          const Icon(Icons.account_balance_outlined, size: 15, color: AppTheme.muted),
                                          const SizedBox(width: 6),
                                          Expanded(child: Text((row['court_name'] ?? 'न्यायालय विवरण नहीं').toString(),
                                            maxLines: 1, overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 12, color: AppTheme.muted))),
                                        ],
                                      ),
                                      const SizedBox(height: 9),
                                      Wrap(
                                        spacing: 10,
                                        runSpacing: 8,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        children: [
                                          Row(mainAxisSize: MainAxisSize.min, children: [
                                            Icon(Icons.event_outlined, size: 15, color: AppTheme.blue),
                                            const SizedBox(width: 6),
                                            Text('अगली पेशी: ${row['next_hearing'] ?? '-'}',
                                              style: const TextStyle(fontSize: 12, color: AppTheme.ink, fontWeight: FontWeight.w600)),
                                          ]),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                            decoration: BoxDecoration(
                                              color: _statusColor(status).withValues(alpha: .10),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _statusColor(status))),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
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

class _EmptyCases extends StatelessWidget {
  const _EmptyCases({required this.searching, required this.onAdd, required this.onClear});
  final bool searching;
  final VoidCallback onAdd;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: const Color(0xFFEAF0FA), borderRadius: BorderRadius.circular(22)),
            child: const Icon(Icons.folder_open_rounded, size: 38, color: AppTheme.blue),
          ),
          const SizedBox(height: 16),
          Text(searching ? 'कोई रिकॉर्ड नहीं मिला' : 'अभी कोई मुकदमा दर्ज नहीं है',
            style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(searching ? 'दूसरे नाम, ST NO या मु0अ0सं0 से खोजें।' : 'नया मुकदमा जोड़कर अपनी सूची तैयार करें।',
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          if (searching)
            OutlinedButton.icon(onPressed: onClear, icon: const Icon(Icons.close), label: const Text('खोज हटाएँ'))
          else
            FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('नया मुकदमा जोड़ें')),
        ],
      ),
    ),
  );
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

  Widget _field(String label, TextEditingController c, {bool required = false, int lines = 1, IconData? icon}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: c,
          maxLines: lines,
          decoration: InputDecoration(labelText: label, prefixIcon: icon == null ? null : Icon(icon, size: 19)),
          validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'यह विवरण आवश्यक है' : null : null,
        ),
      );

  String? _validateHearingDate(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    final parts = text.split('/');
    if (parts.length != 3) return 'तारीख DD/MM/YYYY में भरें';
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null || year < 1900 || year > 2100) {
      return 'मान्य तारीख DD/MM/YYYY में भरें';
    }
    final date = DateTime(year, month, day);
    if (date.day != day || date.month != month || date.year != year) {
      return 'यह कैलेंडर तारीख मान्य नहीं है';
    }
    return null;
  }

  Widget _section(String title, IconData icon, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(15),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, color: AppTheme.blue, size: 19), const SizedBox(width: 8),
          Text(title, style: Theme.of(context).textTheme.titleMedium)]),
        const SizedBox(height: 14),
        ...children,
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, keyboardInset + 12),
        child: Form(
          key: _formKey,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .88),
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: Container(width: 38, height: 4,
                        decoration: BoxDecoration(color: AppTheme.line, borderRadius: BorderRadius.circular(4)))),
                      const SizedBox(height: 16),
                      Text(widget.initial == null ? 'नया मुकदमा जोड़ें' : 'मुकदमा अपडेट करें',
                        style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      const Text('न्यायालयीन रिकॉर्ड का विवरण भरें', style: TextStyle(color: AppTheme.muted, fontSize: 13)),
                      const SizedBox(height: 18),
                      _section('मुकदमे का विवरण', Icons.gavel_rounded, [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final stField = _field('ST NO *', stNo, required: true, icon: Icons.numbers_rounded);
                            final firField = _field('मु0अ0सं0', firNo, icon: Icons.folder_outlined);
                            if (constraints.maxWidth < 390) {
                              return Column(children: [stField, firField]);
                            }
                            return Row(children: [
                              Expanded(child: stField),
                              const SizedBox(width: 10),
                              Expanded(child: firField),
                            ]);
                          },
                        ),
                        _field('धारा', sections, icon: Icons.menu_book_outlined),
                        _field('बनाम / अभियुक्त का नाम *', accused, required: true, icon: Icons.person_outline),
                        _field('न्यायालय', court, icon: Icons.account_balance_outlined),
                      ]),
                      const SizedBox(height: 12),
                      _section('पेशी एवं कार्यवाही', Icons.event_note_rounded, [
                        _field('तलब साक्षी', witnesses, icon: Icons.groups_outlined),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TextFormField(
                            controller: nextHearing,
                            decoration: const InputDecoration(
                              labelText: 'अगली तारीख पेशी (DD/MM/YYYY)',
                              prefixIcon: Icon(Icons.calendar_month_outlined),
                            ),
                            validator: _validateHearingDate,
                          ),
                        ),
                        DropdownButtonFormField<String>(
                          initialValue: status,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'मुकदमे की स्थिति', prefixIcon: Icon(Icons.flag_outlined)),
                          items: {
                            ...const ['साक्ष्य','हाजिरी','बहस','313 सीआरपीसी','सफाई साक्ष्य','जजमेंट','सजा','दोष मुक्त','अभियुक्त NBW'],
                            status,
                          }.map((v) => DropdownMenuItem(value: v, child: Text(v.isEmpty ? 'स्थिति दर्ज नहीं' : v, overflow: TextOverflow.ellipsis))).toList(),
                          onChanged: (v) => setState(() => status = v ?? status),
                        ),
                        const SizedBox(height: 12),
                        _field('कृत कार्यवाही', action, lines: 3, icon: Icons.edit_note_rounded),
                      ]),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('रद्द करें'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
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
                              icon: const Icon(Icons.save_rounded),
                              label: const Text('रिकॉर्ड सेव करें'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
