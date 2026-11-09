import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../data/local_database.dart';
import '../theme/app_theme.dart';

class CaseDocumentsScreen extends StatefulWidget {
  const CaseDocumentsScreen({super.key});
  @override
  State<CaseDocumentsScreen> createState() => _CaseDocumentsScreenState();
}

class _CaseDocumentsScreenState extends State<CaseDocumentsScreen> {
  List<Map<String, Object?>> _cases = [];
  List<Map<String, Object?>> _documents = [];
  String? _caseId;
  String _query = '';
  final TextEditingController _searchController = TextEditingController();
  String _category = 'सभी';
  bool _loading = true;
  bool _adding = false;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cases = await LocalDatabase.instance.searchCases('');
    final selected = _caseId ?? (cases.isNotEmpty ? cases.first['id'].toString() : null);
    final docs = selected == null ? <Map<String, Object?>>[] : await LocalDatabase.instance.caseDocuments(selected);
    if (!mounted) return;
    setState(() { _cases = cases; _caseId = selected; _documents = docs; _loading = false; });
  }

  List<String> get _categories {
    final values = _documents.map((d) => (d['category'] ?? 'अन्य').toString()).where((v) => v.isNotEmpty).toSet().toList()..sort();
    return ['सभी', ...values];
  }

  List<Map<String, Object?>> get _filtered {
    return _documents.where((d) {
      final name = (d['name'] ?? '').toString().toLowerCase();
      final category = (d['category'] ?? 'अन्य').toString();
      final matchesQuery = name.contains(_query.trim().toLowerCase()) || category.toLowerCase().contains(_query.trim().toLowerCase());
      return matchesQuery && (_category == 'सभी' || category == _category);
    }).toList();
  }

  Future<void> _addFile() async {
    if (_caseId == null || _adding) return;
    setState(() => _adding = true);
    try {
      final picked = await FilePicker.platform.pickFiles(withData: false);
      if (picked == null || picked.files.single.path == null) return;
      final source = File(picked.files.single.path!);
      final appDir = await getApplicationDocumentsDirectory();
      final folder = Directory(p.join(appDir.path, 'case_documents', _caseId!));
      await folder.create(recursive: true);
      final id = const Uuid().v4();
      final destination = p.join(folder.path, '${id}_${p.basename(source.path)}');
      await source.copy(destination);
      final extension = p.extension(source.path).replaceFirst('.', '').toUpperCase();
      await LocalDatabase.instance.addCaseDocument(
        id: id, caseId: _caseId!, name: picked.files.single.name,
        category: extension.isEmpty ? 'FILE' : extension,
        path: destination, groupId: id,
      );
      await LocalDatabase.instance.logAction('DOCUMENT_ATTACHED', 'CASE_DOCUMENTS', id, picked.files.single.name);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('दस्तावेज जोड़ने में समस्या: $e')));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _addVersion(Map<String, Object?> doc) async {
    if (_caseId == null) return;
    try {
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
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('नया संस्करण जोड़ने में समस्या: $e')));
    }
  }

  Future<void> _openFile(Map<String, Object?> doc) async {
    final file = File(doc['local_path'].toString());
    if (!await file.exists()) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('फाइल इस स्थान पर उपलब्ध नहीं है।')));
      return;
    }
    await FilePicker.platform.saveFile(fileName: p.basename(file.path), bytes: await file.readAsBytes());
  }

  IconData _fileIcon(String category) {
    switch (category.toUpperCase()) {
      case 'PDF': return Icons.picture_as_pdf_rounded;
      case 'JPG': case 'JPEG': case 'PNG': case 'WEBP': return Icons.image_rounded;
      case 'DOC': case 'DOCX': return Icons.article_rounded;
      case 'XLS': case 'XLSX': return Icons.table_chart_rounded;
      default: return Icons.insert_drive_file_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final docs = _filtered;
    return Scaffold(
      appBar: AppBar(title: const Text('दस्तावेज़ लाइब्रेरी'), actions: [
        IconButton(tooltip: 'रीफ्रेश', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
      ]),
      floatingActionButton: _cases.isEmpty ? null : FloatingActionButton.extended(
        onPressed: _adding ? null : _addFile,
        icon: _adding ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.add_rounded),
        label: Text(_adding ? 'जोड़ा जा रहा है…' : 'दस्तावेज जोड़ें'),
      ),
      body: _loading ? const Center(child: CircularProgressIndicator()) :
        _cases.isEmpty ? const _DocumentsEmpty(icon: Icons.folder_off_rounded, title: 'पहले मुकदमा जोड़ें', subtitle: 'Session Court में मुकदमा दर्ज करने के बाद उसके दस्तावेज यहाँ सुरक्षित कर सकेंगे।')
        : Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
            decoration: const BoxDecoration(color: AppTheme.navy, borderRadius: BorderRadius.vertical(bottom: Radius.circular(24))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Case Document Library', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              const Text('मुकदमे से जुड़े दस्तावेज़ सुरक्षित रखें', style: TextStyle(color: Color(0xFFD4DEED), fontSize: 12)),
              const SizedBox(height: 15),
              DropdownButtonFormField<String>(
                initialValue: _caseId, isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'मुकदमा चुनें', prefixIcon: const Icon(Icons.gavel_rounded),
                  filled: true, fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
                items: _cases.map((c) => DropdownMenuItem(value: c['id'].toString(),
                  child: Text('ST ${c['st_no']} • ${c['accused_name']}', overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) async { setState(() { _caseId = v; _loading = true; _category = 'सभी'; _query = ''; _searchController.clear(); }); await _load(); },
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 8),
            child: Row(children: [
              Expanded(child: _MetricCard(icon: Icons.folder_copy_rounded, label: 'कुल दस्तावेज़', value: '${_documents.length}', color: AppTheme.blue)),
              const SizedBox(width: 10),
              Expanded(child: _MetricCard(icon: Icons.category_rounded, label: 'श्रेणियाँ', value: '${_categories.length - 1}', color: AppTheme.teal)),
            ]),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 10), child: TextField(
            onChanged: (v) => setState(() => _query = v),
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'दस्तावेज़ का नाम खोजें…', prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty ? null : IconButton(onPressed: () { _searchController.clear(); setState(() => _query = ''); }, icon: const Icon(Icons.close_rounded)),
              filled: true, fillColor: Colors.white, contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppTheme.line)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppTheme.line)),
            ),
          )),
          if (_documents.isNotEmpty)
            SizedBox(height: 42, child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16), scrollDirection: Axis.horizontal,
              itemCount: _categories.length, separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final value = _categories[i];
                final selected = _category == value;
                return ChoiceChip(label: Text(value), selected: selected,
                  onSelected: (_) => setState(() => _category = value),
                  selectedColor: AppTheme.navy, backgroundColor: Colors.white,
                  showCheckmark: false,
                  labelStyle: TextStyle(color: selected ? Colors.white : AppTheme.muted, fontWeight: FontWeight.w600, fontSize: 12),
                  side: BorderSide(color: selected ? AppTheme.navy : AppTheme.line));
              },
            )),
          const SizedBox(height: 8),
          Expanded(child: docs.isEmpty
            ? _DocumentsEmpty(icon: _documents.isEmpty ? Icons.folder_open_rounded : Icons.search_off_rounded,
                title: _documents.isEmpty ? 'अभी दस्तावेज़ नहीं हैं' : 'कोई दस्तावेज़ नहीं मिला',
                subtitle: _documents.isEmpty ? 'इस मुकदमे की चार्जशीट, आदेश, समन और अन्य फाइलें जोड़ें।' : 'खोज या श्रेणी बदलकर दोबारा देखें।')
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 100),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final d = docs[i];
                  final category = (d['category'] ?? 'FILE').toString();
                  return Card(
                    margin: const EdgeInsets.only(bottom: 9),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                      leading: Container(width: 46, height: 46,
                        decoration: BoxDecoration(color: const Color(0xFFEAF0FA), borderRadius: BorderRadius.circular(13)),
                        child: Icon(_fileIcon(category), color: AppTheme.blue, size: 23)),
                      title: Text(d['name'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.ink, fontSize: 13)),
                      subtitle: Padding(padding: const EdgeInsets.only(top: 5), child: Wrap(spacing: 7, runSpacing: 5, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        _Tag(text: category),
                        _Tag(text: 'संस्करण ${d['version'] ?? 1}', color: AppTheme.teal),
                      ])),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'अन्य विकल्प',
                        onSelected: (v) { if (v == 'version') _addVersion(d); if (v == 'open') _openFile(d); },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'open', child: ListTile(dense: true, leading: Icon(Icons.download_rounded), title: Text('फाइल सेव करें'))),
                          PopupMenuItem(value: 'version', child: ListTile(dense: true, leading: Icon(Icons.history_rounded), title: Text('नया संस्करण'))),
                        ],
                      ),
                      onTap: () => _openFile(d),
                    ),
                  );
                },
              )),
        ]),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.icon, required this.label, required this.value, required this.color});
  final IconData icon;
  final String label, value;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: AppTheme.line)),
    child: Row(children: [
      Icon(icon, color: color, size: 21), const SizedBox(width: 9),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.muted)),
      ])),
    ]),
  );
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, this.color = AppTheme.blue});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: .09), borderRadius: BorderRadius.circular(20)),
    child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
  );
}

class _DocumentsEmpty extends StatelessWidget {
  const _DocumentsEmpty({required this.icon, required this.title, required this.subtitle});
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
