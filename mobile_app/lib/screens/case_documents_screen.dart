import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../data/local_database.dart';

class CaseDocumentsScreen extends StatefulWidget {
  const CaseDocumentsScreen({super.key});
  @override
  State<CaseDocumentsScreen> createState() => _CaseDocumentsScreenState();
}

class _CaseDocumentsScreenState extends State<CaseDocumentsScreen> {
  List<Map<String, Object?>> _cases = [];
  List<Map<String, Object?>> _documents = [];
  String? _caseId;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final cases = await LocalDatabase.instance.searchCases('');
    final selected = _caseId ?? (cases.isNotEmpty ? cases.first['id'].toString() : null);
    final docs = selected == null ? <Map<String, Object?>>[] : await LocalDatabase.instance.caseDocuments(selected);
    if (!mounted) return;
    setState(() { _cases = cases; _caseId = selected; _documents = docs; _loading = false; });
  }

  Future<void> _addFile() async {
    if (_caseId == null) return;
    final picked = await FilePicker.platform.pickFiles(withData: false);
    if (picked == null || picked.files.single.path == null) return;
    final source = File(picked.files.single.path!);
    final appDir = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(appDir.path, 'case_documents', _caseId!));
    await folder.create(recursive: true);
    final id = const Uuid().v4();
    final destination = p.join(folder.path, '${id}_${p.basename(source.path)}');
    await source.copy(destination);
    await LocalDatabase.instance.addCaseDocument(
      id: id, caseId: _caseId!, name: picked.files.single.name,
      category: p.extension(source.path).replaceFirst('.', '').toUpperCase(),
      path: destination, groupId: id,
    );
    await LocalDatabase.instance.logAction('DOCUMENT_ATTACHED', 'CASE_DOCUMENTS', id, picked.files.single.name);
    await _load();
  }

  Future<void> _addVersion(Map<String, Object?> doc) async {
    final picked = await FilePicker.platform.pickFiles(withData: false);
    if (picked == null || picked.files.single.path == null) return;
    final source = File(picked.files.single.path!);
    final appDir = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(appDir.path, 'case_documents', _caseId!));
    await folder.create(recursive: true);
    final id = const Uuid().v4();
    final version = (doc['version'] as int? ?? 1) + 1;
    final destination = p.join(folder.path, '${id}_${p.basename(source.path)}');
    await source.copy(destination);
    await LocalDatabase.instance.addDocumentVersion(
      id: id, groupId: doc['document_group_id'].toString(),
      documentId: doc['id'].toString(), version: version, path: destination,
      remarks: 'नया संस्करण जोड़ा गया',
    );
    await LocalDatabase.instance.updateDocumentVersion(doc['id'].toString(), version, destination);
    await LocalDatabase.instance.logAction('DOCUMENT_VERSION_ADDED', 'CASE_DOCUMENTS', doc['id'].toString(), 'Version $version');
    await _load();
  }

  Future<void> _openFile(Map<String, Object?> doc) async {
    final file = File(doc['local_path'].toString());
    if (!await file.exists()) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('फाइल इस स्थान पर उपलब्ध नहीं है।')));
      return;
    }
    await FilePicker.platform.saveFile(fileName: p.basename(file.path), bytes: await file.readAsBytes());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Case Document Library')),
    floatingActionButton: _cases.isEmpty ? null : FloatingActionButton.extended(
      onPressed: _addFile, icon: const Icon(Icons.attach_file), label: const Text('दस्तावेज जोड़ें')),
    body: _loading ? const Center(child: CircularProgressIndicator()) : _cases.isEmpty
      ? const Center(child: Text('पहले Session Court में मुकदमा जोड़ें।'))
      : Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: DropdownButtonFormField<String>(
          value: _caseId, isExpanded: true,
          decoration: const InputDecoration(labelText: 'मुकदमा चुनें', border: OutlineInputBorder()),
          items: _cases.map((c) => DropdownMenuItem(value: c['id'].toString(),
            child: Text('ST ${c['st_no']} • ${c['accused_name']}', overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) async { setState(() { _caseId = v; _loading = true; }); await _load(); },
        )),
        Expanded(child: _documents.isEmpty
          ? const Center(child: Text('इस मुकदमे में अभी दस्तावेज नहीं हैं।'))
          : ListView.builder(padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
            itemCount: _documents.length, itemBuilder: (_, i) {
              final d = _documents[i];
              return Card(child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.description)),
                title: Text(d['name'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text('${d['category']} • संस्करण ${d['version']}\n${d['remarks'] ?? ''}'),
                isThreeLine: true,
                onTap: () => _openFile(d),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) { if (v == 'version') _addVersion(d); if (v == 'open') _openFile(d); },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'open', child: Text('फाइल सेव/खोलें')),
                    PopupMenuItem(value: 'version', child: Text('नया संस्करण जोड़ें')),
                  ],
                ),
              ));
            })),
      ]),
  );
}
