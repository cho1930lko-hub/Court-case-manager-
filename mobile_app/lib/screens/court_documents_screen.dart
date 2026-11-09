import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../data/local_database.dart';
import '../theme/app_theme.dart';

class CourtDocumentsScreen extends StatefulWidget {
  const CourtDocumentsScreen({super.key});

  @override
  State<CourtDocumentsScreen> createState() => _CourtDocumentsScreenState();
}

class _CourtDocumentsScreenState extends State<CourtDocumentsScreen> {
  List<Map<String, Object?>> _cases = [];
  String? _caseId;
  String _type = 'समन';
  final _witness = TextEditingController();
  final _hearingDate = TextEditingController();
  final _court = TextEditingController();
  final _remarks = TextEditingController();
  String _preview = '';
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadCases();
  }

  @override
  void dispose() {
    _witness.dispose();
    _hearingDate.dispose();
    _court.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _loadCases() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final rows = await LocalDatabase.instance.searchCases('');
      if (!mounted) return;
      setState(() {
        _cases = rows;
        if (rows.isNotEmpty) {
          _caseId = rows.first['id']?.toString();
          _court.text = (rows.first['court_name'] ?? '').toString();
          _hearingDate.text = (rows.first['next_hearing'] ?? '').toString();
        } else {
          _caseId = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadError = 'मुकदमों का रिकॉर्ड लोड नहीं हो सका।');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, Object?>? get _selected {
    for (final row in _cases) {
      if (row['id']?.toString() == _caseId) return row;
    }
    return null;
  }

  String _makeDocument() {
    final c = _selected;
    if (c == null) return 'पहले मुकदमा चुनें।';
    final st = (c['st_no'] ?? '').toString();
    final fir = (c['fir_no'] ?? '').toString();
    final accused = (c['accused_name'] ?? '').toString();
    final sections = (c['sections'] ?? '').toString();
    final court = _court.text.trim().isEmpty
        ? (c['court_name'] ?? '').toString()
        : _court.text.trim();
    final date = _hearingDate.text.trim().isEmpty
        ? (c['next_hearing'] ?? '').toString()
        : _hearingDate.text.trim();

    if (_type == 'समन') {
      return 'न्यायालय: $court\nमुकदमा संख्या (ST No.): $st\nमु0अ0सं0: $fir\nधारा: $sections\nराज्य बनाम: $accused\n\n'
          'समन हेतु साक्षी: ${_witness.text.trim()}\nनियत पेशी: $date\n\n'
          'कृपया नियत तिथि पर माननीय न्यायालय के समक्ष उपस्थित होकर साक्ष्य प्रदान करें।\n\n'
          'नोट: यह प्रारूप है। जारी करने से पहले न्यायालय/कार्यालय के निर्धारित प्रारूप एवं विवरण का मिलान करें।';
    }
    return 'सेवा में,\nन्यायालय श्रीमान $court महोदय\n\n'
        'विषयः मुकदमा ST No. $st, मु0अ0सं0 $fir धारा $sections, राज्य बनाम $accused में कार्यवाही आख्या।\n\n'
        'महोदय, सादर निवेदन है कि उपरोक्त मुकदमे में नियत पेशी दिनांक $date पर की गई कार्यवाही का विवरण निम्नवत हैः\n\n'
        '${_remarks.text.trim()}\n\nअतः सादर अवगत कराना है।\n\nदिनांक: __________\nपैरकार / थाना: __________\n\n'
        'नोट: प्रस्तुत करने से पूर्व तथ्यों एवं न्यायालय के अभिलेख से मिलान करें।';
  }

  Future<void> _generate() async {
    if (_selected == null || _saving) return;
    setState(() => _saving = true);
    final text = _makeDocument();
    try {
      await LocalDatabase.instance.saveGeneratedDocument(
        id: const Uuid().v4(),
        caseId: _caseId!,
        type: _type,
        content: text,
      );
      await LocalDatabase.instance.logAction(
        'DOCUMENT_DRAFT_CREATED',
        'COURT_DOCUMENTS',
        _caseId!,
        '$_type draft for ST No. ${_selected!['st_no']}',
      );
      if (!mounted) return;
      setState(() => _preview = text);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ड्राफ्ट सुरक्षित कर दिया गया है।')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ड्राफ्ट सुरक्षित नहीं हो सका। पुनः प्रयास करें।')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _sectionTitle(String title, String subtitle, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppTheme.blue.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppTheme.blue, size: 20),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('समन एवं कार्यवाही आख्या'),
        actions: [
          IconButton(
            tooltip: 'मुकदमों की सूची रीफ्रेश करें',
            onPressed: _loading ? null : _loadCases,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _LoadError(message: _loadError!, onRetry: _loadCases)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.navy, AppTheme.blue],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: const Icon(Icons.edit_document, color: Colors.white, size: 25),
                          ),
                          const SizedBox(width: 13),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('न्यायालयीन ड्राफ्ट', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                                SizedBox(height: 4),
                                Text('मुकदमे के रिकॉर्ड से प्रारंभिक विवरण भरें और ड्राफ्ट तैयार करें।', style: TextStyle(color: Colors.white70, height: 1.35, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionTitle('दस्तावेज का विवरण', 'ड्राफ्ट का प्रकार और संबंधित मुकदमा चुनें', Icons.folder_open_rounded),
                            const SizedBox(height: 17),
                            DropdownButtonFormField<String>(
                              initialValue: _type,
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'दस्तावेज का प्रकार', prefixIcon: Icon(Icons.description_outlined)),
                              items: const [
                                DropdownMenuItem(value: 'समन', child: Text('समन')),
                                DropdownMenuItem(value: 'कार्यवाही आख्या', child: Text('कार्यवाही आख्या')),
                              ],
                              onChanged: (value) => setState(() {
                                _type = value ?? _type;
                                _preview = '';
                              }),
                            ),
                            const SizedBox(height: 13),
                            if (_cases.isEmpty)
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(color: AppTheme.canvas, borderRadius: BorderRadius.circular(13)),
                                child: const Row(
                                  children: [
                                    Icon(Icons.info_outline, color: AppTheme.muted),
                                    SizedBox(width: 10),
                                    Expanded(child: Text('पहले Session Court में मुकदमा जोड़ें।')),
                                  ],
                                ),
                              )
                            else
                              DropdownButtonFormField<String>(
                                initialValue: _caseId,
                                isExpanded: true,
                                decoration: const InputDecoration(labelText: 'मुकदमा चुनें', prefixIcon: Icon(Icons.gavel_rounded)),
                                items: _cases.map((c) => DropdownMenuItem(
                                  value: c['id'].toString(),
                                  child: Text('ST ${c['st_no']}  •  ${c['accused_name']}', overflow: TextOverflow.ellipsis),
                                )).toList(),
                                onChanged: (value) => setState(() {
                                  _caseId = value;
                                  _preview = '';
                                  final row = _selected;
                                  _court.text = (row?['court_name'] ?? '').toString();
                                  _hearingDate.text = (row?['next_hearing'] ?? '').toString();
                                }),
                              ),
                            if (selected != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(color: AppTheme.canvas, borderRadius: BorderRadius.circular(12)),
                                child: Row(
                                  children: [
                                    const Icon(Icons.person_outline, size: 18, color: AppTheme.muted),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text('अभियुक्त: ${selected['accused_name'] ?? '—'}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                                    Text('ST ${selected['st_no'] ?? '—'}', style: const TextStyle(color: AppTheme.blue, fontWeight: FontWeight.w700, fontSize: 12)),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionTitle('आवश्यक जानकारी', 'रिकॉर्ड से भरे विवरण को आवश्यकतानुसार संशोधित करें', Icons.assignment_outlined),
                            const SizedBox(height: 17),
                            TextField(
                              controller: _court,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(labelText: 'न्यायालय का नाम', prefixIcon: Icon(Icons.account_balance_outlined)),
                            ),
                            const SizedBox(height: 13),
                            TextField(
                              controller: _hearingDate,
                              keyboardType: TextInputType.datetime,
                              decoration: const InputDecoration(labelText: 'नियत पेशी दिनांक', hintText: 'DD/MM/YYYY', prefixIcon: Icon(Icons.calendar_month_outlined)),
                            ),
                            const SizedBox(height: 13),
                            if (_type == 'समन')
                              TextField(
                                controller: _witness,
                                maxLines: 2,
                                textCapitalization: TextCapitalization.words,
                                decoration: const InputDecoration(labelText: 'साक्षी का नाम / पता', alignLabelWithHint: true, prefixIcon: Icon(Icons.person_search_outlined)),
                              )
                            else
                              TextField(
                                controller: _remarks,
                                maxLines: 5,
                                textCapitalization: TextCapitalization.sentences,
                                decoration: const InputDecoration(labelText: 'की गई कार्यवाही का विवरण', hintText: 'गवाह की उपस्थिति, तामील की स्थिति अथवा अन्य तथ्य लिखें…', alignLabelWithHint: true, prefixIcon: Icon(Icons.notes_rounded)),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: selected == null || _saving ? null : _generate,
                      icon: _saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.auto_awesome_rounded),
                      label: Text(_saving ? 'ड्राफ्ट सुरक्षित हो रहा है…' : 'ड्राफ्ट तैयार करें'),
                    ),
                    if (_preview.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(child: Text('ड्राफ्ट प्रीव्यू', style: Theme.of(context).textTheme.titleLarge)),
                          TextButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: _preview));
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ड्राफ्ट कॉपी हो गया।')));
                            },
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            label: const Text('कॉपी करें'),
                          ),
                        ],
                      ),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(17),
                          child: SelectableText(_preview, style: const TextStyle(height: 1.7, fontSize: 14, color: AppTheme.ink)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, size: 17, color: AppTheme.muted),
                          SizedBox(width: 7),
                          Expanded(child: Text('यह प्रारंभिक ड्राफ्ट है। प्रस्तुत/जारी करने से पहले सभी तथ्यों और न्यायालय के निर्धारित प्रारूप का मिलान अवश्य करें।', style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4))),
                        ],
                      ),
                    ],
                  ],
                ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 42, color: AppTheme.muted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('पुनः प्रयास करें')),
          ],
        ),
      ),
    );
  }
}
