import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/local_database.dart';
import '../theme/app_theme.dart';

/// Central metadata manager. Field metadata is stored locally in SQLCipher.
class FieldManagerScreen extends StatefulWidget {
  const FieldManagerScreen({super.key});
  @override
  State<FieldManagerScreen> createState() => _FieldManagerScreenState();
}

class _FieldManagerScreenState extends State<FieldManagerScreen> {
  static const _modules = <String, String>{
    'cases': 'सेशन कोर्ट',
    'dak_register': 'डाक रजिस्टर',
    'remand_register': 'रिमांड रजिस्टर',
    'address_book': 'Address Book',
  };
  String _module = 'cases';
  List<Map<String, Object?>> _fields = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await LocalDatabase.instance.getFieldDefinitions(_module);
    if (!mounted) return;
    setState(() { _fields = rows; _loading = false; });
  }

  Future<void> _addField() async {
    final label = TextEditingController();
    final key = TextEditingController();
    final options = TextEditingController();
    String type = 'text';
    bool requiredField = false;
    String roles = 'admin,staff';
    final result = await showDialog<bool>(context: context, builder: (dialogContext) =>
      StatefulBuilder(builder: (context, setDialog) => AlertDialog(
        title: const Text('नया फील्ड बनाएँ'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: label, decoration: const InputDecoration(labelText: 'फील्ड का नाम')),
          const SizedBox(height: 8),
          TextField(controller: key, decoration: const InputDecoration(labelText: 'Unique Key (जैसे witness_count)')),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(initialValue: type, decoration: const InputDecoration(labelText: 'फील्ड प्रकार'),
            items: const [
              DropdownMenuItem(value: 'text', child: Text('Text')),
              DropdownMenuItem(value: 'number', child: Text('Number')),
              DropdownMenuItem(value: 'date', child: Text('Date')),
              DropdownMenuItem(value: 'dropdown', child: Text('Dropdown')),
              DropdownMenuItem(value: 'multiline', child: Text('लंबा विवरण')),
              DropdownMenuItem(value: 'boolean', child: Text('हाँ / नहीं')),
            ], onChanged: (v) => setDialog(() => type = v ?? 'text')),
          if (type == 'dropdown') ...[
            const SizedBox(height: 8),
            TextField(controller: options, maxLines: 3,
              decoration: const InputDecoration(labelText: 'Dropdown विकल्प', hintText: 'हर विकल्प नई लाइन में')),
          ],
          CheckboxListTile(value: requiredField, contentPadding: EdgeInsets.zero,
            title: const Text('अनिवार्य फील्ड'), onChanged: (v) => setDialog(() => requiredField = v ?? false)),
          DropdownButtonFormField<String>(initialValue: roles,
            decoration: const InputDecoration(labelText: 'किसे बदलाव की अनुमति?'),
            items: const [
              DropdownMenuItem(value: 'admin', child: Text('केवल Admin')),
              DropdownMenuItem(value: 'admin,staff', child: Text('Admin और अधिकृत कर्मचारी')),
              DropdownMenuItem(value: 'admin,staff,viewer', child: Text('सभी भूमिकाएँ')),
            ], onChanged: (v) => setDialog(() => roles = v ?? 'admin,staff')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('रद्द')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('फील्ड बनाएँ')),
        ],
      )));
    if (result != true) return;
    final fieldLabel = label.text.trim();
    final fieldKey = key.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]+'), '_');
    if (fieldLabel.isEmpty || fieldKey.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('नाम और Unique Key आवश्यक हैं।')));
      return;
    }
    try {
      final id = const Uuid().v4();
      await LocalDatabase.instance.saveFieldDefinition(id: id, module: _module,
        fieldKey: fieldKey, label: fieldLabel, dataType: type,
        requiredField: requiredField, allowedRoles: roles);
      if (type == 'dropdown') {
        for (final option in options.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty)) {
          await LocalDatabase.instance.addFieldOption(const Uuid().v4(), id, option);
        }
      }
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('फील्ड नहीं बना: $e')));
    }
  }

  Future<void> _showOptions(Map<String, Object?> field) async {
    final id = field['id'].toString();
    final rows = await LocalDatabase.instance.getFieldOptions(id);
    final controller = TextEditingController();
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: Text('${field['label']} — विकल्प'),
      content: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (rows.isEmpty) const Text('अभी कोई विकल्प नहीं है।'),
        ...rows.map((row) => ListTile(dense: true, leading: const Icon(Icons.radio_button_checked),
          title: Text(row['option_label'].toString()))),
        TextField(controller: controller, decoration: const InputDecoration(labelText: 'नया विकल्प जोड़ें')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('बंद')),
        FilledButton(onPressed: () async {
          final value = controller.text.trim();
          if (value.isNotEmpty) {
            await LocalDatabase.instance.addFieldOption(const Uuid().v4(), id, value);
            if (ctx.mounted) Navigator.pop(ctx);
            await _showOptions(field);
          }
        }, child: const Text('जोड़ें')),
      ],
    ));
  }

  Future<void> _deactivate(Map<String, Object?> field) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('फील्ड बंद करें?'),
      content: const Text('फील्ड और उसके पुराने रिकॉर्ड सुरक्षित रहेंगे; केवल नई एंट्री में छिपेगा।'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('रद्द')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('बंद करें')),
      ],
    ));
    if (ok != true) return;
    try { await LocalDatabase.instance.deactivateFieldDefinition(field['id'].toString()); await _load(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Dynamic Field Manager')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _addField, icon: const Icon(Icons.add), label: const Text('नया फील्ड')),
    body: Column(children: [
      Container(width: double.infinity, padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(color: AppTheme.navy,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(22))),
        child: const Text('रजिस्टर के फील्ड और Dropdown विकल्प नियंत्रित करें। पुराने डेटा को हटाए बिना बदलाव लागू होंगे।',
          style: TextStyle(color: Colors.white, fontSize: 13, height: 1.5))),
      Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: DropdownButtonFormField<String>(initialValue: _module,
          decoration: const InputDecoration(labelText: 'मॉड्यूल चुनें'),
          items: _modules.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
          onChanged: (v) { if (v != null) setState(() => _module = v); _load(); })),
      Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) :
        _fields.isEmpty ? const Center(child: Text('अभी कोई अतिरिक्त फील्ड नहीं है। + दबाकर बनाएँ।')) :
        ListView.separated(padding: const EdgeInsets.all(16), itemCount: _fields.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final field = _fields[index];
            final type = field['data_type'].toString();
            return Card(child: ListTile(
              leading: CircleAvatar(backgroundColor: AppTheme.blue.withValues(alpha: .1),
                child: Icon(type == 'dropdown' ? Icons.arrow_drop_down_circle_outlined : Icons.tune, color: AppTheme.blue)),
              title: Text(field['label'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${field['field_key']} • $type • ${(field['is_required'] == 1) ? 'अनिवार्य' : 'वैकल्पिक'} • ${field['allowed_roles']}'),
              trailing: PopupMenuButton<String>(onSelected: (v) {
                if (v == 'options') _showOptions(field);
                if (v == 'disable') _deactivate(field);
              }, itemBuilder: (_) => [
                if (type == 'dropdown') const PopupMenuItem(value: 'options', child: Text('Dropdown विकल्प')),
                const PopupMenuItem(value: 'disable', child: Text('फील्ड बंद करें')),
              ]),
            ));
          })),
    ]),
  );
}
