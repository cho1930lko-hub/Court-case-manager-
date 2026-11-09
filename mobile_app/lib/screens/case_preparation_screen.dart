import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/local_database.dart';
import '../theme/app_theme.dart';
import 'case_activity_screen.dart';

class CasePreparationScreen extends StatefulWidget {
  const CasePreparationScreen({super.key});
  @override
  State<CasePreparationScreen> createState() => _CasePreparationScreenState();
}

class _CasePreparationScreenState extends State<CasePreparationScreen> {
  List<Map<String, Object?>> _cases = [];
  bool _loading = true;
  String _filter = 'सभी';
  final _search = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _search.dispose(); super.dispose(); }

  DateTime? _date(Object? value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return null;
    for (final f in [DateFormat('dd/MM/yyyy'), DateFormat('d/M/yyyy'), DateFormat('yyyy-MM-dd')]) {
      try { return f.parseStrict(raw); } catch (_) {}
    }
    return null;
  }

  Future<void> _load() async {
    try {
      final data = await LocalDatabase.instance.casePreparationSummary();
      if (mounted) setState(() { _cases = data; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('डेटा लोड नहीं हुआ: $e')));
    }
  }

  List<Map<String, Object?>> get _visible {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final q = _search.text.trim().toLowerCase();
    final visible = _cases.where((c) {
      final d = _date(c['next_hearing']);
      final pending = (c['checklist_pending'] as num?)?.toInt() ?? 0;
      final match = switch (_filter) {
        'आगामी पेशी' => d != null && !d.isBefore(today),
        'पेशी निकल गई' => d != null && d.isBefore(today),
        'लंबित कार्य' => pending > 0,
        _ => true,
      };
      final text = [c['st_no'], c['fir_no'], c['accused_name'], c['court_name']].join(' ').toLowerCase();
      return match && (q.isEmpty || text.contains(q));
    }).toList();

    // The database may contain legacy DD/MM/YYYY text. Never sort those
    // values lexicographically (which puts 05/01/2027 before 10/11/2026).
    visible.sort((a, b) {
      final da = _date(a['next_hearing']);
      final db = _date(b['next_hearing']);
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      final byDate = da.compareTo(db);
      if (byDate != 0) return byDate;
      final sa = int.tryParse((a['st_no'] ?? '').toString()) ?? 0;
      final sb = int.tryParse((b['st_no'] ?? '').toString()) ?? 0;
      return sb.compareTo(sa);
    });
    return visible;
  }

  int get _pending => _cases.fold(0, (v, c) => v + ((c['checklist_pending'] as num?)?.toInt() ?? 0));
  int get _upcoming {
    final n = DateTime.now(); final today = DateTime(n.year, n.month, n.day);
    return _cases.where((c) { final d = _date(c['next_hearing']); return d != null && !d.isBefore(today); }).length;
  }

  Future<void> _open(Map<String, Object?> c) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CaseActivityScreen(initialCaseId: c['id'].toString())));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    return Scaffold(
      appBar: AppBar(title: const Text('अगली पेशी की तैयारी'),
        actions: [IconButton(onPressed: _loading ? null : _load, tooltip: 'रीफ्रेश', icon: const Icon(Icons.refresh_rounded))]),
      body: _loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 28), children: [
          Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: AppTheme.navy, borderRadius: BorderRadius.circular(18)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [Icon(Icons.event_available_rounded, color: Color(0xFFB9D8D2)), SizedBox(width: 8), Text('Court Preparation Desk', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))]),
              const SizedBox(height: 8),
              const Text('अगली पेशी से पहले जरूरी काम पहचानें', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              Row(children: [
                _metric(_cases.length.toString(), 'कुल मुकदमे'),
                const SizedBox(width: 8), _metric(_upcoming.toString(), 'आगामी पेशी'),
                const SizedBox(width: 8), _metric(_pending.toString(), 'लंबित कार्य'),
              ]),
            ])),
          const SizedBox(height: 16),
          TextField(controller: _search, onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: 'ST नंबर, FIR, अभियुक्त या न्यायालय खोजें', prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.text.isEmpty ? null : IconButton(onPressed: () { _search.clear(); setState(() {}); }, icon: const Icon(Icons.close_rounded)))),
          const SizedBox(height: 10),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
            for (final f in ['सभी', 'आगामी पेशी', 'पेशी निकल गई', 'लंबित कार्य'])
              Padding(padding: const EdgeInsets.only(right: 7), child: ChoiceChip(label: Text(f), selected: _filter == f, showCheckmark: false, onSelected: (_) => setState(() => _filter = f))),
          ])),
          const SizedBox(height: 10),
          if (rows.isEmpty) Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(children: [
            const Icon(Icons.event_busy_rounded, size: 34, color: AppTheme.muted), const SizedBox(height: 9),
            Text(_cases.isEmpty ? 'अभी कोई मुकदमा दर्ज नहीं है' : 'इस फ़िल्टर में कोई मुकदमा नहीं मिला', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 5), const Text('मुकदमे की अगली पेशी और Checklist अपडेट रखने पर यहाँ तैयारी का सारांश दिखेगा।', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.muted, fontSize: 12)),
          ])))
          else for (final c in rows) _caseCard(c, _date(c['next_hearing']), () => _open(c)),
          const SizedBox(height: 8),
          const Text('यह तैयारी-सहायक मौजूदा रिकॉर्ड पर आधारित है। पेशी, समन और कार्यवाही की वास्तविक स्थिति मूल अभिलेख से सत्यापित करें।', style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4)),
        ]),
      ),
    );
  }

  Widget _metric(String value, String label) => Expanded(child: Container(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 5),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .10), borderRadius: BorderRadius.circular(11)),
    child: Column(children: [Text(value, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)), Text(label, style: const TextStyle(color: Color(0xFFD5DDE8), fontSize: 10))])));

  Widget _caseCard(Map<String, Object?> c, DateTime? date, VoidCallback onTap) {
    final pending = (c['checklist_pending'] as num?)?.toInt() ?? 0;
    final done = (c['checklist_done'] as num?)?.toInt() ?? 0;
    final total = (c['checklist_total'] as num?)?.toInt() ?? 0;
    final rawDate = (c['next_hearing'] ?? '').toString().trim();
    final now = DateTime.now(); final today = DateTime(now.year, now.month, now.day);
    final color = date != null && date.isBefore(today) ? const Color(0xFFB65C50) : AppTheme.teal;
    return Card(margin: const EdgeInsets.only(bottom: 10), child: InkWell(
      borderRadius: BorderRadius.circular(16), onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text('ST ' + (c['st_no'] ?? '—').toString() + '  •  मु0अ0सं0 ' + (c['fir_no'] ?? '—').toString(), style: const TextStyle(color: AppTheme.blue, fontWeight: FontWeight.w800, fontSize: 12))), const Icon(Icons.chevron_right_rounded, color: AppTheme.muted)]),
        const SizedBox(height: 7),
        Text('राज्य बनाम ' + (c['accused_name'] ?? '—').toString(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.ink)),
        if ((c['court_name'] ?? '').toString().trim().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(c['court_name'].toString(), style: const TextStyle(color: AppTheme.muted, fontSize: 12))),
        const SizedBox(height: 11),
        Wrap(spacing: 7, runSpacing: 7, children: [
          _tag(Icons.event_outlined, rawDate.isEmpty ? 'पेशी दर्ज नहीं' : 'पेशी: ' + rawDate, color),
          _tag(Icons.pending_actions_rounded, '$pending लंबित कार्य', pending > 0 ? const Color(0xFFAD762D) : AppTheme.teal),
          _tag(Icons.check_circle_outline_rounded, '$done/$total पूर्ण', AppTheme.blue),
        ]),
        if (total > 0) Padding(padding: const EdgeInsets.only(top: 11), child: ClipRRect(borderRadius: BorderRadius.circular(20), child: LinearProgressIndicator(value: done / total, minHeight: 6, backgroundColor: AppTheme.line, color: AppTheme.teal))),
        const SizedBox(height: 8),
        const Align(alignment: Alignment.centerRight, child: Text('Timeline और Checklist खोलें  →', style: TextStyle(color: AppTheme.blue, fontWeight: FontWeight.w700, fontSize: 11))),
      ])),
    ));
  }

  Widget _tag(IconData icon, String label, Color color) => Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(color: color.withValues(alpha: .09), borderRadius: BorderRadius.circular(9)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 13, color: color), const SizedBox(width: 5), Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700))]));
}
