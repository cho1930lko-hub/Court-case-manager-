import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../data/local_database.dart';

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
      if (mounted) setState(() { _cases = []; _loading = false; });
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
      context: context, builder: (_) => const _EntryDialog(title: 'कार्यवाही दर्ज करें', fields: ['दिनांक (DD/MM/YYYY)', 'कार्यवाही का प्रकार', 'विवरण']),
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
      context: context, builder: (_) => const _EntryDialog(title: 'नई Checklist', fields: ['कार्य', 'अंतिम तिथि (DD/MM/YYYY)', 'जिम्मेदार व्यक्ति', 'टिप्पणी']),
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
    await LocalDatabase.instance.logAction(done ? 'TASK_COMPLETED' : 'TASK_REOPENED', 'CASE_CHECKLIST', task['id'].toString(), task['task_name'].toString());
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Case Timeline & Checklist')),
      floatingActionButton: _cases.isEmpty ? null : FloatingActionButton.extended(
        onPressed: _tab == 0 ? _addTimeline : _addTask,
        icon: const Icon(Icons.add), label: Text(_tab == 0 ? 'कार्यवाही जोड़ें' : 'कार्य जोड़ें'),
      ),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _cases.isEmpty
        ? const Center(child: Text('पहले Session Court में मुकदमा जोड़ें।'))
        : Column(children: [
          Padding(padding: const EdgeInsets.all(12), child: DropdownButtonFormField<String>(
            value: _caseId, isExpanded: true,
            decoration: const InputDecoration(labelText: 'मुकदमा चुनें', border: OutlineInputBorder()),
            items: _cases.map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text('ST ${c['st_no']} • ${c['accused_name']}', overflow: TextOverflow.ellipsis))).toList(),
            onChanged: _selectCase,
          )),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Timeline'), icon: Icon(Icons.timeline)),
              ButtonSegment(value: 1, label: Text('Checklist'), icon: Icon(Icons.checklist)),
            ],
            selected: {_tab}, onSelectionChanged: (v) => setState(() => _tab = v.first),
          )),
          Expanded(child: _tab == 0 ? _timelineList() : _taskList()),
        ]),
    );
  }

  Widget _timelineList() => _events.isEmpty
    ? const Center(child: Text('अभी कोई कार्यवाही दर्ज नहीं है।'))
    : ListView.builder(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), itemCount: _events.length, itemBuilder: (_, i) {
        final e = _events[i];
        return Card(child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.event_note)),
          title: Text(e['event_type'].toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('${e['event_date']}\n${e['description']}'),
          isThreeLine: true,
        ));
      });

  Widget _taskList() => _tasks.isEmpty
    ? const Center(child: Text('अभी कोई लंबित कार्य नहीं है।'))
    : ListView.builder(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), itemCount: _tasks.length, itemBuilder: (_, i) {
        final t = _tasks[i];
        final done = t['status'] == 'पूर्ण';
        return Card(child: CheckboxListTile(
          value: done, onChanged: (v) => _toggleTask(t, v ?? false),
          title: Text(t['task_name'].toString(), style: TextStyle(fontWeight: FontWeight.w600, decoration: done ? TextDecoration.lineThrough : null)),
          subtitle: Text('अंतिम तिथि: ${t['due_date']} • जिम्मेदार: ${t['assigned_to']}\n${t['remarks']}'),
          secondary: Icon(done ? Icons.check_circle : Icons.pending_actions, color: done ? Colors.green : Colors.orange),
        ));
      });
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
    title: Text(widget.title),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < widget.fields.length; i++)
        Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(
          controller: controllers[i], maxLines: i == widget.fields.length - 1 ? 3 : 1,
          decoration: InputDecoration(labelText: widget.fields[i], border: const OutlineInputBorder()),
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
