import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../data/local_database.dart';

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

  @override
  void initState() { super.initState(); _loadCases(); }

  @override
  void dispose() {
    _witness.dispose(); _hearingDate.dispose(); _court.dispose(); _remarks.dispose();
    super.dispose();
  }

  Future<void> _loadCases() async {
    final rows = await LocalDatabase.instance.searchCases('');
    if (!mounted) return;
    setState(() {
      _cases = rows;
      if (rows.isNotEmpty) {
        _caseId = rows.first['id']?.toString();
        _court.text = (rows.first['court_name'] ?? '').toString();
        _hearingDate.text = (rows.first['next_hearing'] ?? '').toString();
      }
    });
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
    final court = _court.text.trim().isEmpty ? (c['court_name'] ?? '').toString() : _court.text.trim();
    final date = _hearingDate.text.trim().isEmpty ? (c['next_hearing'] ?? '').toString() : _hearingDate.text.trim();
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
    final text = _makeDocument();
    setState(() => _preview = text);
    if (_selected == null) return;
    await LocalDatabase.instance.saveGeneratedDocument(
      id: const Uuid().v4(), caseId: _caseId!, type: _type, content: text);
    await LocalDatabase.instance.logAction('DOCUMENT_DRAFT_CREATED', 'COURT_DOCUMENTS',
      _caseId!, '$_type draft for ST No. ${_selected!['st_no']}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('समन एवं कार्यवाही आख्या')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        DropdownButtonFormField<String>(
          initialValue: _type,
          decoration: const InputDecoration(labelText: 'दस्तावेज का प्रकार', border: OutlineInputBorder()),
          items: const ['समन', 'कार्यवाही आख्या'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          onChanged: (v) => setState(() { _type = v ?? _type; _preview = ''; }),
        ),
        const SizedBox(height: 12),
        if (_cases.isEmpty) const Text('पहले Session Court में मुकदमा जोड़ें।') else
          DropdownButtonFormField<String>(
            initialValue: _caseId, isExpanded: true,
            decoration: const InputDecoration(labelText: 'मुकदमा चुनें', border: OutlineInputBorder()),
            items: _cases.map((c) => DropdownMenuItem(
              value: c['id'].toString(),
              child: Text('ST ${c['st_no']} • ${c['accused_name']}', overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: (v) => setState(() {
              _caseId = v;
              _preview = '';
              final selected = _selected;
              _court.text = (selected?['court_name'] ?? '').toString();
              _hearingDate.text = (selected?['next_hearing'] ?? '').toString();
            }),
          ),
        const SizedBox(height: 12),
        TextField(controller: _court, decoration: const InputDecoration(
          labelText: 'न्यायालय (रिकॉर्ड से स्वतः भरेगा)', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: _hearingDate, decoration: const InputDecoration(
          labelText: 'नियत पेशी दिनांक', hintText: 'DD/MM/YYYY', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        if (_type == 'समन')
          TextField(controller: _witness, maxLines: 2, decoration: const InputDecoration(
            labelText: 'साक्षी का नाम / पता', border: OutlineInputBorder()))
        else
          TextField(controller: _remarks, maxLines: 5, decoration: const InputDecoration(
            labelText: 'की गई कार्यवाही का विवरण', border: OutlineInputBorder())),
        const SizedBox(height: 14),
        FilledButton.icon(onPressed: _generate, icon: const Icon(Icons.description), label: const Text('ड्राफ्ट तैयार करें')),
        if (_preview.isNotEmpty) ...[
          const SizedBox(height: 18),
          Row(children: [
            const Expanded(child: Text('ड्राफ्ट प्रीव्यू', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17))),
            TextButton.icon(onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _preview));
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ड्राफ्ट कॉपी हो गया।')));
            }, icon: const Icon(Icons.copy), label: const Text('कॉपी')),
          ]),
          Card(child: Padding(padding: const EdgeInsets.all(14), child: SelectableText(_preview, style: const TextStyle(height: 1.55)))),
          const Text('यह प्रारंभिक ड्राफ्ट है; जारी/प्रस्तुत करने से पहले तथ्य और निर्धारित प्रारूप जाँचें।',
            style: TextStyle(color: Colors.deepOrange)),
        ],
      ]),
    );
  }
}
