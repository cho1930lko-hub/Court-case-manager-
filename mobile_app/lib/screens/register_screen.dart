import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../data/local_database.dart';

class RegisterField {
  const RegisterField(this.key, this.label, {this.lines = 1, this.required = false});
  final String key, label;
  final int lines;
  final bool required;
}

class RegisterConfig {
  const RegisterConfig({required this.title, required this.table, required this.fields,
    required this.titleField, required this.subtitleFields});
  final String title, table, titleField;
  final List<RegisterField> fields;
  final List<String> subtitleFields;
}

const dakConfig = RegisterConfig(title: 'Dak Register', table: 'dak_register',
  titleField: 'st_no', subtitleFields: ['dak_type', 'accused_name', 'court_name'],
  fields: [
    RegisterField('st_no', 'ST NO / पत्रांक'),
    RegisterField('dak_type', 'डाक का प्रकार', required: true),
    RegisterField('accused_name', 'अभियुक्त / संबंधित व्यक्ति'),
    RegisterField('status', 'स्थिति'),
    RegisterField('person_address', 'व्यक्ति का पता', lines: 2),
    RegisterField('related_station', 'संबंधित थाना'),
    RegisterField('court_name', 'न्यायालय / कार्यालय'),
    RegisterField('station_received_date', 'थाना प्राप्ति दिनांक'),
    RegisterField('hearing_date', 'पेशी दिनांक'),
    RegisterField('remarks', 'टिप्पणी', lines: 3),
  ]);

const remandConfig = RegisterConfig(title: 'Rimand Register', table: 'remand_register',
  titleField: 'fir_no', subtitleFields: ['remand_date', 'court_name', 'accused_details'],
  fields: [
    RegisterField('remand_date', 'रिमांड दिनांक', required: true),
    RegisterField('fir_no', 'मु0अ0सं0', required: true),
    RegisterField('sections', 'धारा'),
    RegisterField('court_name', 'न्यायालय'),
    RegisterField('investigating_officer', 'विवेचक'),
    RegisterField('first_remand_date', 'प्रथम रिमांड दिनांक'),
    RegisterField('accused_details', 'अभियुक्त का विवरण', lines: 3),
  ]);

const addressConfig = RegisterConfig(title: 'Address Book', table: 'address_book',
  titleField: 'name', subtitleFields: ['mobile', 'department', 'address'],
  fields: [
    RegisterField('name', 'नाम', required: true),
    RegisterField('mobile', 'मोबाइल नंबर'),
    RegisterField('department', 'पद / विभाग'),
    RegisterField('address', 'पूरा पता', lines: 3),
  ]);

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.config});
  final RegisterConfig config;
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _search = TextEditingController();
  List<Map<String, Object?>> _rows = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); _search.addListener(_load); }

  @override
  void dispose() { _search.removeListener(_load); _search.dispose(); super.dispose(); }

  Future<void> _load() async {
    final rows = await LocalDatabase.instance.searchRegister(widget.config.table, _search.text);
    if (!mounted) return;
    setState(() { _rows = rows; _loading = false; });
  }

  Future<void> _edit([Map<String, Object?>? row]) async {
    final result = await showModalBottomSheet<Map<String, Object?>>(
      context: context, isScrollControlled: true, useSafeArea: true,
      builder: (_) => _RegisterForm(config: widget.config, initial: row));
    if (result == null) return;
    final id = (row?['id'] ?? const Uuid().v4()).toString();
    try {
      await LocalDatabase.instance.saveRegister(widget.config.table, result, id: id, isNew: row == null);
      await LocalDatabase.instance.logAction(row == null ? 'REGISTER_CREATED' : 'REGISTER_UPDATED',
        widget.config.table, id, widget.config.title + ': ' + (result[widget.config.titleField] ?? '').toString());
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(row == null ? 'रिकॉर्ड सेव हो गया।' : 'रिकॉर्ड अपडेट हो गया।')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('सेव नहीं हुआ: ' + e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    return Scaffold(
      appBar: AppBar(title: Text(config.title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('नई एंट्री')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 8), child: TextField(
          controller: _search,
          decoration: InputDecoration(hintText: 'रिकॉर्ड खोजें...', prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(onPressed: _search.clear, icon: const Icon(Icons.close)),
            filled: true, fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)))),
        Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) :
          _rows.isEmpty ? const Center(child: Text('अभी कोई रिकॉर्ड नहीं है। नई एंट्री से शुरुआत करें।')) :
          RefreshIndicator(onRefresh: _load, child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 90), itemCount: _rows.length,
            itemBuilder: (context, index) {
              final row = _rows[index];
              final title = (row[config.titleField] ?? '').toString();
              final subtitle = config.subtitleFields.map((key) => (row[key] ?? '').toString())
                .where((value) => value.trim().isNotEmpty).join(' • ');
              return Card(child: ListTile(onTap: () => _edit(row),
                leading: const CircleAvatar(child: Icon(Icons.description_outlined)),
                title: Text(title.isEmpty ? 'बिना शीर्षक रिकॉर्ड' : title,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(subtitle.isEmpty ? 'विवरण जोड़ने के लिए खोलें' : subtitle),
                trailing: const Icon(Icons.edit_outlined)));
            }))),
      ]),
    );
  }
}

class _RegisterForm extends StatefulWidget {
  const _RegisterForm({required this.config, this.initial});
  final RegisterConfig config;
  final Map<String, Object?>? initial;
  @override
  State<_RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<_RegisterForm> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    for (final field in widget.config.fields) {
      _controllers[field.key] = TextEditingController(text: (widget.initial?[field.key] ?? '').toString());
    }
  }

  @override
  void dispose() { for (final c in _controllers.values) { c.dispose(); } super.dispose(); }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(18, 18, 18, MediaQuery.of(context).viewInsets.bottom + 18),
    child: Form(key: _formKey, child: SingleChildScrollView(child: Column(
      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.initial == null ? 'नई एंट्री जोड़ें' : 'एंट्री संशोधित करें',
          style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 14),
        for (final field in widget.config.fields)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: TextFormField(
            controller: _controllers[field.key], maxLines: field.lines,
            decoration: InputDecoration(labelText: field.label, border: const OutlineInputBorder()),
            validator: field.required ? (v) => v == null || v.trim().isEmpty ? 'यह विवरण आवश्यक है' : null : null)),
        FilledButton.icon(onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(context, {for (final e in _controllers.entries) e.key: e.value.text.trim()});
        }, icon: const Icon(Icons.save), label: const Text('सेव करें')),
      ],
    ))),
  );
}
