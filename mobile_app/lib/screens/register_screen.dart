import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../services/dak_attachment_service.dart';

import '../data/local_database.dart';
import '../theme/app_theme.dart';
import 'import_export_screen.dart';

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

  IconData get _icon {
    if (widget.config.table == 'dak_register') return Icons.mark_email_unread_rounded;
    if (widget.config.table == 'remand_register') return Icons.assignment_turned_in_rounded;
    return Icons.contact_phone_rounded;
  }

  Color get _accent {
    if (widget.config.table == 'dak_register') return AppTheme.teal;
    if (widget.config.table == 'remand_register') return const Color(0xFFC47B28);
    return const Color(0xFF7655B5);
  }

  String get _description {
    if (widget.config.table == 'dak_register') return 'प्राप्त डाक, संबंधित व्यक्ति और न्यायालयीन पत्राचार';
    if (widget.config.table == 'remand_register') return 'रिमांड की तारीख, मुकदमा और अभियुक्त का विवरण';
    return 'अधिकारी, गवाह और विभागीय संपर्क विवरण';
  }

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
      backgroundColor: AppTheme.canvas,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _RegisterForm(config: widget.config, initial: row));
    if (result == null) return;
    final id = (row?['id'] ?? const Uuid().v4()).toString();
    String? committedAttachment;
    final stagedAttachment = result['__dak_attachment_staged']?.toString() ?? '';
    result.remove('__dak_attachment_staged');
    if (stagedAttachment.isNotEmpty) {
      try {
        committedAttachment = await DakAttachmentService.instance.commit(stagedAttachment, id);
        result['attachment_path'] = committedAttachment;
      } catch (e) {
        await DakAttachmentService.instance.discard(stagedAttachment);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('अटैचमेंट सेव नहीं हुआ: $e')));
        return;
      }
    }
    final values = <String, Object?>{};
    final customValues = <String, String>{};
    for (final entry in result.entries) {
      if (entry.key.startsWith('__custom__:')) {
        customValues[entry.key.substring(11)] = entry.value.toString();
      } else {
        values[entry.key] = entry.value;
      }
    }
    try {
      await LocalDatabase.instance.saveWithAudit(
        table: widget.config.table, values: values, recordId: id, isNew: row == null,
        customFieldValues: customValues,
        action: row == null ? 'REGISTER_CREATED' : 'REGISTER_UPDATED',
        module: widget.config.table,
        details: widget.config.title + ': ' + (values[widget.config.titleField] ?? '').toString(),
      );
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(row == null ? 'रिकॉर्ड सेव हो गया।' : 'रिकॉर्ड अपडेट हो गया।')));
    } catch (e) {
      if (committedAttachment != null) {
        final file = File(committedAttachment);
        if (await file.exists()) await file.delete();
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('सेव नहीं हुआ: ' + e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    return Scaffold(
      appBar: AppBar(title: Text(config.title), actions: [
        IconButton(tooltip: 'Excel Import / Export', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ImportExportScreen(initialModule: widget.config.table))), icon: const Icon(Icons.import_export_rounded)),
        IconButton(tooltip: 'रीफ्रेश', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        const SizedBox(width: 4),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(), icon: const Icon(Icons.add_rounded), label: const Text('नई एंट्री')),
      body: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 19, 18, 18),
          decoration: const BoxDecoration(color: AppTheme.navy,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(24))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 46, height: 46,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: .13), borderRadius: BorderRadius.circular(14)),
                child: Icon(_icon, color: Colors.white, size: 23)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(config.title, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(_description, style: const TextStyle(color: Color(0xFFD4DEED), fontSize: 11)),
              ])),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              const Icon(Icons.folder_copy_outlined, size: 16, color: Color(0xFFB8F1DD)),
              const SizedBox(width: 6),
              Text('${_rows.length} रिकॉर्ड', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 13),
            TextField(
              controller: _search,
              style: const TextStyle(color: AppTheme.ink),
              decoration: InputDecoration(
                hintText: 'इस रजिस्टर में खोजें...',
                prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.muted),
                suffixIcon: _search.text.isEmpty ? null : IconButton(onPressed: _search.clear, icon: const Icon(Icons.close_rounded)),
                filled: true, fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              ),
            ),
          ]),
        ),
        Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) :
          _rows.isEmpty ? _EmptyRegister(searching: _search.text.isNotEmpty, accent: _accent,
            onAdd: () => _edit(), onClear: _search.clear) :
          RefreshIndicator(onRefresh: _load, child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: _rows.length, separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final row = _rows[index];
              final title = (row[config.titleField] ?? '').toString();
              final details = config.subtitleFields.map((key) => (row[key] ?? '').toString())
                .where((value) => value.trim().isNotEmpty).toList();
              return Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => _edit(row),
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(width: 43, height: 43,
                        decoration: BoxDecoration(color: _accent.withValues(alpha: .10), borderRadius: BorderRadius.circular(13)),
                        child: Icon(_icon, color: _accent, size: 21)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title.isEmpty ? 'बिना शीर्षक रिकॉर्ड' : title,
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.ink)),
                        const SizedBox(height: 6),
                        if (details.isEmpty)
                          const Text('विवरण जोड़ने के लिए खोलें', style: TextStyle(fontSize: 12, color: AppTheme.muted))
                        else
                          ...details.map((value) => Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
                          )),
                      ])),
                      const SizedBox(width: 5),
                      const Icon(Icons.chevron_right_rounded, color: AppTheme.muted),
                    ]),
                  ),
                ),
              );
            }))),
      ]),
    );
  }
}

class _EmptyRegister extends StatelessWidget {
  const _EmptyRegister({required this.searching, required this.accent, required this.onAdd, required this.onClear});
  final bool searching;
  final Color accent;
  final VoidCallback onAdd, onClear;

  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(30),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: accent.withValues(alpha: .10), borderRadius: BorderRadius.circular(22)),
        child: Icon(Icons.inbox_outlined, size: 38, color: accent)),
      const SizedBox(height: 16),
      Text(searching ? 'कोई रिकॉर्ड नहीं मिला' : 'रजिस्टर अभी खाली है',
        style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      Text(searching ? 'दूसरे शब्दों से खोजकर देखें।' : 'नई एंट्री जोड़कर रजिस्टर शुरू करें।',
        textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 16),
      if (searching)
        OutlinedButton.icon(onPressed: onClear, icon: const Icon(Icons.close), label: const Text('खोज हटाएँ'))
      else
        FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('नई एंट्री')),
    ]),
  ));
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
  List<Map<String, Object?>> _customFields = [];
  final Map<String, TextEditingController> _customControllers = {};
  final Map<String, String> _customDropdowns = {};
  final Map<String, List<Map<String, Object?>>> _customOptions = {};
  String _dakAttachmentPath = '';
  String? _stagedDakAttachment;
  bool _handedOffStagedAttachment = false;

  @override
  void initState() {
    super.initState();
    _dakAttachmentPath = (widget.initial?['attachment_path'] ?? '').toString();
    for (final field in widget.config.fields) {
      _controllers[field.key] = TextEditingController(text: (widget.initial?[field.key] ?? '').toString());
    }
    _loadCustomFields();
  }

  Future<void> _loadCustomFields() async {
    final module = widget.config.table;
    final fields = await LocalDatabase.instance.getFieldDefinitions(module);
    final values = widget.initial == null ? <String, String>{} :
      await LocalDatabase.instance.getCustomFieldValues(module, widget.initial!['id'].toString());
    for (final field in fields) {
      final id = field['id'].toString();
      final type = field['data_type'].toString();
      if (type == 'dropdown') {
        _customOptions[id] = await LocalDatabase.instance.getFieldOptions(id);
        _customDropdowns[id] = values[id] ?? '';
      } else {
        _customControllers[id] = TextEditingController(text: values[id] ?? '');
      }
    }
    if (mounted) setState(() => _customFields = fields);
  }

  @override
  void dispose() {
    if (!_handedOffStagedAttachment) {
      unawaited(DakAttachmentService.instance.discard(_stagedDakAttachment));
    }
    for (final c in _controllers.values) { c.dispose(); }
    for (final c in _customControllers.values) { c.dispose(); }
    super.dispose();
  }

  IconData _fieldIcon(String key) {
    switch (key) {
      case 'st_no': return Icons.numbers_rounded;
      case 'fir_no': return Icons.folder_outlined;
      case 'name': return Icons.person_outline;
      case 'mobile': return Icons.phone_outlined;
      case 'address':
      case 'person_address': return Icons.location_on_outlined;
      case 'court_name': return Icons.account_balance_outlined;
      case 'remand_date':
      case 'first_remand_date':
      case 'hearing_date':
      case 'station_received_date': return Icons.calendar_month_outlined;
      case 'remarks':
      case 'accused_details': return Icons.notes_rounded;
      default: return Icons.edit_note_rounded;
    }
  }

  bool _isDateField(String key) => const {
    'remand_date', 'first_remand_date', 'hearing_date', 'station_received_date',
  }.contains(key);

  Future<void> _pickDate(String key) async {
    final controller = _controllers[key]!;
    DateTime initial = DateTime.now();
    final raw = controller.text.trim();
    final parts = raw.split('/');
    if (parts.length == 3) {
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (day != null && month != null && year != null) {
        final candidate = DateTime(year, month, day);
        if (candidate.day == day && candidate.month == month && candidate.year == year) initial = candidate;
      }
    } else {
      initial = DateTime.tryParse(raw) ?? initial;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1990),
      lastDate: DateTime(2100),
      helpText: 'दिनांक चुनें',
      cancelText: 'रद्द करें',
      confirmText: 'चुनें',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(colorScheme: Theme.of(context).colorScheme.copyWith(primary: AppTheme.blue)),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    final day = picked.day.toString().padLeft(2, '0');
    final month = picked.month.toString().padLeft(2, '0');
    controller.text = '$day/$month/${picked.year}';
    setState(() {});
  }


  Future<void> _pickDakAttachment() async {
    try {
      final staged = await DakAttachmentService.instance.pickAndStage();
      if (staged == null) return;
      if (!mounted) {
        await DakAttachmentService.instance.discard(staged);
        return;
      }
      await DakAttachmentService.instance.discard(_stagedDakAttachment);
      setState(() => _stagedDakAttachment = staged);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('फाइल नहीं चुनी गई: $e')),
      );
    }
  }

  Widget _dakAttachmentCard() {
    if (widget.config.table != 'dak_register') return const SizedBox.shrink();
    final path = _stagedDakAttachment ?? _dakAttachmentPath;
    final hasFile = path.trim().isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.attach_file_rounded, color: AppTheme.blue),
            const SizedBox(width: 8),
            Expanded(child: Text('डाक का संलग्नक', style: Theme.of(context).textTheme.titleMedium)),
            TextButton.icon(
              onPressed: _pickDakAttachment,
              icon: const Icon(Icons.upload_file_rounded),
              label: Text(hasFile ? 'बदलें' : 'फाइल जोड़ें'),
            ),
          ]),
          if (hasFile) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.insert_drive_file_outlined, color: AppTheme.muted),
              const SizedBox(width: 8),
              Expanded(child: Text(p.basename(path), maxLines: 2, overflow: TextOverflow.ellipsis)),
              IconButton(
                tooltip: 'संलग्नक हटाएँ',
                onPressed: () async {
                  await DakAttachmentService.instance.discard(_stagedDakAttachment);
                  setState(() {
                    _stagedDakAttachment = null;
                    _dakAttachmentPath = '';
                  });
                },
                icon: const Icon(Icons.close_rounded),
              ),
            ]),
          ] else
            const Text('PDF, JPG, PNG, DOCX या XLSX • अधिकतम 20 MB',
              style: TextStyle(fontSize: 12, color: AppTheme.muted)),
        ]),
      ),
    );
  }

  List<Map<String, Object?>> _formSections() {
    if (widget.config.table == 'dak_register') {
      return [
        {'title': 'डाक का विवरण', 'icon': Icons.mail_outline_rounded, 'fields': ['st_no', 'dak_type', 'status']},
        {'title': 'संबंधित व्यक्ति एवं थाना', 'icon': Icons.person_pin_circle_outlined, 'fields': ['accused_name', 'person_address', 'related_station']},
        {'title': 'न्यायालय एवं तारीख', 'icon': Icons.account_balance_outlined, 'fields': ['court_name', 'station_received_date', 'hearing_date']},
        {'title': 'अतिरिक्त टिप्पणी', 'icon': Icons.notes_rounded, 'fields': ['remarks']},
      ];
    }
    if (widget.config.table == 'remand_register') {
      return [
        {'title': 'मुकदमे का विवरण', 'icon': Icons.folder_outlined, 'fields': ['remand_date', 'fir_no', 'sections']},
        {'title': 'न्यायालय एवं विवेचना', 'icon': Icons.account_balance_outlined, 'fields': ['court_name', 'investigating_officer', 'first_remand_date']},
        {'title': 'अभियुक्त का विवरण', 'icon': Icons.person_outline, 'fields': ['accused_details']},
      ];
    }
    return [
      {'title': 'संपर्क विवरण', 'icon': Icons.contact_phone_outlined, 'fields': ['name', 'mobile', 'department']},
      {'title': 'पता', 'icon': Icons.location_on_outlined, 'fields': ['address']},
    ];
  }

  Widget _buildField(RegisterField field) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: _controllers[field.key],
      maxLines: field.lines,
      textInputAction: field.lines > 1 ? TextInputAction.newline : TextInputAction.next,
      keyboardType: field.key == 'mobile' ? TextInputType.phone : TextInputType.text,
      readOnly: _isDateField(field.key),
      onTap: _isDateField(field.key) ? () => _pickDate(field.key) : null,
      decoration: InputDecoration(
        labelText: field.required ? '${field.label} *' : field.label,
        alignLabelWithHint: field.lines > 1,
        prefixIcon: Icon(_fieldIcon(field.key), size: 19),
        suffixIcon: _isDateField(field.key) && (_controllers[field.key]?.text.isNotEmpty ?? false)
            ? IconButton(
                tooltip: 'दिनांक हटाएँ',
                onPressed: () => setState(() => _controllers[field.key]!.clear()),
                icon: const Icon(Icons.close_rounded, size: 18),
              )
            : _isDateField(field.key) ? const Icon(Icons.calendar_month_outlined) : null,
      ),
      validator: (v) {
        final value = (v ?? '').trim();
        if (field.required && value.isEmpty) return 'यह विवरण आवश्यक है';
        if (field.key == 'mobile' && value.isNotEmpty) {
          final normalized = value.replaceAll(RegExp(r'[\s-]'), '');
          if (!RegExp(r'^(?:\+?91)?[6-9]\d{9}$').hasMatch(normalized)) {
            return '10 अंकों का सही मोबाइल नंबर दर्ज करें';
          }
        }
        return null;
      },
    ),
  );

  Widget _customFieldsCard() {
    if (_customFields.isEmpty) return const SizedBox.shrink();
    return Card(child: Padding(
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.tune_rounded, color: AppTheme.blue, size: 19),
          const SizedBox(width: 8),
          Text('अतिरिक्त / Custom Fields', style: Theme.of(context).textTheme.titleMedium),
        ]),
        const SizedBox(height: 14),
        for (final field in _customFields) ...[
          Builder(builder: (context) {
            final id = field['id'].toString();
            final label = field['label'].toString();
            final type = field['data_type'].toString();
            final requiredField = field['is_required'] == 1;
            if (type == 'dropdown') {
              final options = _customOptions[id] ?? [];
              final current = _customDropdowns[id];
              return Padding(padding: const EdgeInsets.only(bottom: 12),
                child: DropdownButtonFormField<String>(
                  initialValue: current != null && current.isNotEmpty && options.any((o) => o['option_label'] == current) ? current : null,
                  decoration: InputDecoration(labelText: requiredField ? '$label *' : label),
                  items: options.map((o) => DropdownMenuItem(value: o['option_label'].toString(), child: Text(o['option_label'].toString()))).toList(),
                  onChanged: (v) => setState(() => _customDropdowns[id] = v ?? ''),
                  validator: requiredField ? (v) => (v == null || v.isEmpty) ? 'यह विवरण आवश्यक है' : null : null,
                ));
            }
            final controller = _customControllers[id]!;
            return Padding(padding: const EdgeInsets.only(bottom: 12),
              child: TextFormField(
                controller: controller,
                maxLines: type == 'multiline' ? 3 : 1,
                keyboardType: type == 'number' ? TextInputType.number : TextInputType.text,
                decoration: InputDecoration(labelText: requiredField ? '$label *' : label),
                validator: requiredField ? (v) => (v == null || v.trim().isEmpty) ? 'यह विवरण आवश्यक है' : null : null,
              ));
          }),
        ],
      ]),
    ));
  }

  Widget _sectionCard(Map<String, Object?> section) {
    final keys = section['fields'] as List<String>;
    final fields = widget.config.fields.where((field) => keys.contains(field.key));
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 15, 15, 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.blue.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(section['icon'] as IconData, color: AppTheme.blue, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(
                section['title'] as String,
                style: Theme.of(context).textTheme.titleMedium,
              )),
            ]),
            const SizedBox(height: 15),
            for (final field in fields) _buildField(field),
          ],
        ),
      ),
    );
  }

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
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: Container(width: 38, height: 4,
                        decoration: BoxDecoration(color: AppTheme.line, borderRadius: BorderRadius.circular(4)))),
                      const SizedBox(height: 16),
                      Text(widget.initial == null ? 'नई एंट्री जोड़ें' : 'एंट्री संशोधित करें',
                        style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      Text(widget.config.title, style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
                      const SizedBox(height: 18),
                      for (final section in _formSections()) ...[
                        _sectionCard(section),
                        const SizedBox(height: 12),
                      ],
                      _dakAttachmentCard(),
                      if (widget.config.table == 'dak_register') const SizedBox(height: 12),
                      _customFieldsCard(),
                      if (_customFields.isNotEmpty) const SizedBox(height: 12),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                await DakAttachmentService.instance.discard(_stagedDakAttachment);
                                if (context.mounted) Navigator.pop(context);
                              },
                              child: const Text('रद्द करें'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed: () {
                                if (!_formKey.currentState!.validate()) return;
                                _handedOffStagedAttachment = true;
                                Navigator.pop(context, {
                                  for (final e in _controllers.entries) e.key: e.value.text.trim(),
                                  if (widget.config.table == 'dak_register') 'attachment_path': _dakAttachmentPath,
                                  if (_stagedDakAttachment != null) '__dak_attachment_staged': _stagedDakAttachment!,
                                  for (final e in _customControllers.entries) '__custom__:${e.key}': e.value.text.trim(),
                                  for (final e in _customDropdowns.entries) '__custom__:${e.key}': e.value,
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
