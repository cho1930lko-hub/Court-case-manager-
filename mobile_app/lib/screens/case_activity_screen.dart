import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/local_database.dart';
import '../theme/app_theme.dart';

class CaseActivityScreen extends StatefulWidget {
  const CaseActivityScreen({super.key});
  @override
  State<CaseActivityScreen> createState() => _CaseActivityScreenState();
}

class _CaseActivityScreenState extends State<CaseActivityScreen> {
  List<Map<String, Object?>> _cases = [];
  String? _caseId;
  int _tab = 0;
  List<Map<String, Object?>> _events = [];
  List<Map<String, Object?>> _tasks = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final cases = await LocalDatabase.instance.searchCases('');
    if (cases.isEmpty) {
      if (mounted) setState(() { _cases = []; _events = []; _tasks = []; _loading = false; });
      return;
    }
    final selected = _caseId ?? cases.first['id'].toString();
    final events = await LocalDatabase.instance.caseTimeline(selected);
    final tasks = await LocalDatabase.instance.caseChecklist(selected);
    if (!mounted) return;
    setState(() { _cases = cases; _caseId = selected; _events = events; _tasks = tasks; _loading = false; });
  }

  Future<void> _selectCase(String? id) async {
    if (id == null) return;
    setState(() { _caseId = id; _loading = true; });
    await _load();
  }

  Future<void> _addTimeline() async {
    final form = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _EntryDialog(title: 'कार्यवाही दर्ज करें',
        fields: ['दिनांक (DD/MM/YYYY)', 'कार्यवाही का प्रकार', 'विवरण']),
    );
    if (form == null || _caseId == null) return;
    await LocalDatabase.instance.addTimelineEvent(
      id: const Uuid().v4(), caseId: _caseId!,
      date: form['दिनांक (DD/MM/YYYY)']!, type: form['कार्यवाही का प्रकार']!, description: form['विवरण']!,
    );
    await LocalDatabase.instance.logAction('TIMELINE_ADDED', 'CASE_TIMELINE', _caseId!, form['कार्यवाही का प्रकार']!);
    await _load();
  }

  Future<void> _addTask() async {
    final form = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _EntryDialog(title: 'नई Checklist',
        fields: ['कार्य', 'अंतिम तिथि (DD/MM/YYYY)', 'जिम्मेदार व्यक्ति', 'टिप्पणी']),
    );
    if (form == null || _caseId == null) return;
    await LocalDatabase.instance.addChecklistTask(
      id: const Uuid().v4(), caseId: _caseId!, task: form['कार्य']!,
      dueDate: form['अंतिम तिथि (DD/MM/YYYY)']!, assignedTo: form['जिम्मेदार व्यक्ति']!, remarks: form['टिप्पणी']!,
    );
    await LocalDatabase.instance.logAction('CHECKLIST_ADDED', 'CASE_CHECKLIST', _caseId!, form['कार्य']!);
    await _load();
  }

  Future<void> _toggleTask(Map<String, Object?> task, bool done) async {
    await LocalDatabase.instance.setChecklistStatus(task['id'].toString(), done);
    await LocalDatabase.instance.logAction(done ? 'TASK_COMPLETED' : 'TASK_REOPENED',
      'CASE_CHECKLIST', task['id'].toString(), task['task_name'].toString());
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final matchingCases = _cases.where((c) => c['id']?.toString() == _caseId);
    final selectedCase = matchingCases.isEmpty ? null : matchingCases.first;
    final pending = _tasks.where((t) => t['status'] != 'पूर्ण').length;
    final completed = _tasks.length - pending;
    return Scaffold(
      appBar: AppBar(title: const Text('Timeline & Checklist'), actions: [
        IconButton(tooltip: 'रीफ्रेश', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        const SizedBox(width: 4),
      ]),
      floatingActionButton: _cases.isEmpty ? null : FloatingActionButton.extended(
        onPressed: _tab == 0 ? _addTimeline : _addTask,
        icon: const Icon(Icons.add_rounded),
        label: Text(_tab == 0 ? 'कार्यवाही जोड़ें' : 'कार्य जोड़ें'),
      ),
      body: _loading ? const Center(child: CircularProgressIndicator()) :
        _cases.isEmpty ? const _NoCases() : Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            decoration: const BoxDecoration(color: AppTheme.navy,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('केस गतिविधि प्रबंधन', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              const Text('हर पेशी की कार्यवाही और जरूरी काम एक जगह', style: TextStyle(color: Color(0xFFD4DEED), fontSize: 12)),
              const SizedBox(height: 15),
              DropdownButtonFormField<String>(
                initialValue: _caseId, isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'मुकदमा चुनें', labelStyle: const TextStyle(color: AppTheme.muted),
                  prefixIcon: const Icon(Icons.gavel_rounded),
                  filled: true, fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
                items: _cases.map((c) => DropdownMenuItem(
                  value: c['id'].toString(),
                  child: Text('ST ${c['st_no']} • ${c['accused_name']}', overflow: TextOverflow.ellipsis),
                )).toList(),
                onChanged: _selectCase,
              ),
              if (selectedCase != null) ...[
                const SizedBox(height: 12),
                Text('राज्य बनाम ${selectedCase['accused_name'] ?? '-'}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
              ],
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 12),
            child: Row(children: [
              Expanded(child: _SummaryPill(icon: Icons.timeline_rounded, label: 'कार्यवाही', value: _events.length, color: AppTheme.blue)),
              const SizedBox(width: 9),
              Expanded(child: _SummaryPill(icon: Icons.pending_actions_rounded, label: 'लंबित', value: pending, color: const Color(0xFFC47B28))),
              const SizedBox(width: 9),
              Expanded(child: _SummaryPill(icon: Icons.check_circle_outline_rounded, label: 'पूर्ण', value: completed, color: AppTheme.teal)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, label: Text('Timeline'), icon: Icon(Icons.timeline_rounded)),
                ButtonSegment(value: 1, label: Text('Checklist'), icon: Icon(Icons.checklist_rounded)),
              ],
              selected: {_tab}, onSelectionChanged: (v) => setState(() => _tab = v.first),
            ),
          ),
          Expanded(child: _tab == 0 ? _timelineList() : _taskList()),
        ]),
    );
  }

  Widget _timelineList() => _events.isEmpty
    ? const _EmptyActivity(icon: Icons.timeline_rounded, title: 'अभी कोई कार्यवाही दर्ज नहीं है',
        subtitle: 'नई कार्यवाही जोड़कर केस की तारीखवार गतिविधि सुरक्षित करें।')
    : ListView.builder(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 100),
        itemCount: _events.length,
        itemBuilder: (_, i) {
          final e = _events[i];
          final isLast = i == _events.length - 1;
          return IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: 28, child: Column(children: [
                Container(width: 13, height: 13, decoration: BoxDecoration(
                  color: AppTheme.blue, shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFDCE8F8), width: 3))),
                if (!isLast) Expanded(child: Container(width: 2, color: AppTheme.line)),
              ])),
              const SizedBox(width: 10),
              Expanded(child: Padding(
                padding: const EdgeInsets.only(bottom: 13),
                child: Card(child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(e['event_type'].toString(),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.ink))),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(color: const Color(0xFFEAF0FA), borderRadius: BorderRadius.circular(20)),
                        child: Text(e['event_date'].toString(), style: const TextStyle(fontSize: 10, color: AppTheme.blue, fontWeight: FontWeight.w700))),
                    ]),
                    const SizedBox(height: 8),
                    Text(e['description'].toString(), style: const TextStyle(fontSize: 13, color: AppTheme.muted, height: 1.45)),
                  ]),
                )),
              )),
            ]),
          );
        },
      );

  Widget _taskList() {
    final completed = _tasks.where((t) => t['status'] == 'पूर्ण').length;
    return _tasks.isEmpty
    ? const _EmptyActivity(icon: Icons.checklist_rounded, title: 'अभी कोई Checklist नहीं है',
        subtitle: 'जरूरी कार्य जोड़ें और पूरा होने पर टिक करें।')
    : ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
        children: [
          Card(child: Padding(padding: const EdgeInsets.all(13), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Expanded(child: Text('कार्य पूर्णता', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink))),
                Text('$completed / ${_tasks.length} पूर्ण', style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
              ]),
              const SizedBox(height: 9),
              ClipRRect(borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(value: _tasks.isEmpty ? 0 : completed / _tasks.length,
                  minHeight: 8, backgroundColor: AppTheme.line, color: AppTheme.teal)),
            ],
          ))),
          const SizedBox(height: 8),
          for (final t in _tasks) _TaskCard(task: t, onChanged: (done) => _toggleTask(t, done)),
        ],
      );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.icon, required this.label, required this.value, required this.color});
  final IconData icon;
  final String label;
  final int value;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppTheme.line)),
    child: Row(children: [
      Icon(icon, color: color, size: 17),
      const SizedBox(width: 7),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$value', style: TextStyle(fontSize: 18, color: color, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.muted)),
      ])),
    ]),
  );
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.onChanged});
  final Map<String, Object?> task;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    final done = task['status'] == 'पूर्ण';
    final due = (task['due_date'] ?? '').toString();
    final assigned = (task['assigned_to'] ?? '').toString();
    final remarks = (task['remarks'] ?? '').toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 14, 12),
        child: Column(children: [
          Row(children: [
            Checkbox(value: done, onChanged: (v) => onChanged(v ?? false)),
            Expanded(child: Text(task['task_name'].toString(),
              style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.ink,
                decoration: done ? TextDecoration.lineThrough : null,
                decorationColor: AppTheme.muted))),
            Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: (done ? AppTheme.teal : const Color(0xFFC47B28)).withValues(alpha: .10),
                borderRadius: BorderRadius.circular(20)),
              child: Text(done ? 'पूर्ण' : 'लंबित', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                color: done ? AppTheme.teal : const Color(0xFFC47B28)))),
          ]),
          if (due.isNotEmpty || assigned.isNotEmpty || remarks.isNotEmpty)
            Padding(padding: const EdgeInsets.only(left: 42, top: 2),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (due.isNotEmpty || assigned.isNotEmpty)
                  Wrap(spacing: 14, runSpacing: 5, children: [
                    if (due.isNotEmpty) _Meta(icon: Icons.event_outlined, text: due),
                    if (assigned.isNotEmpty) _Meta(icon: Icons.person_outline, text: assigned),
                  ]),
                if (remarks.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6),
                  child: Text(remarks, style: const TextStyle(fontSize: 12, color: AppTheme.muted))),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 13, color: AppTheme.muted), const SizedBox(width: 4),
    Text(text, style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
  ]);
}

class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(30),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: const Color(0xFFEAF0FA), borderRadius: BorderRadius.circular(22)),
        child: Icon(icon, size: 38, color: AppTheme.blue)),
      const SizedBox(height: 15),
      Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
      const SizedBox(height: 6),
      Text(subtitle, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
    ]),
  ));
}

class _NoCases extends StatelessWidget {
  const _NoCases();
  @override
  Widget build(BuildContext context) => const _EmptyActivity(
    icon: Icons.folder_off_outlined, title: 'पहले मुकदमा जोड़ें',
    subtitle: 'Timeline और Checklist शुरू करने के लिए Session Court में मुकदमा दर्ज करें।');
}

class _EntryDialog extends StatefulWidget {
  const _EntryDialog({required this.title, required this.fields});
  final String title;
  final List<String> fields;
  @override
  State<_EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<_EntryDialog> {
  late final List<TextEditingController> controllers;
  @override
  void initState() { super.initState(); controllers = List.generate(widget.fields.length, (_) => TextEditingController()); }
  @override
  void dispose() { for (final c in controllers) { c.dispose(); } super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    title: Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < widget.fields.length; i++)
        Padding(padding: const EdgeInsets.only(bottom: 11), child: TextField(
          controller: controllers[i], maxLines: i == widget.fields.length - 1 ? 3 : 1,
          decoration: InputDecoration(labelText: widget.fields[i]),
        )),
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('रद्द')),
      FilledButton(onPressed: () {
        final values = <String, String>{};
        for (var i = 0; i < widget.fields.length; i++) { values[widget.fields[i]] = controllers[i].text.trim(); }
        if (values.values.any((v) => v.isEmpty)) return;
        Navigator.pop(context, values);
      }, child: const Text('सेव करें')),
    ],
  );
}
