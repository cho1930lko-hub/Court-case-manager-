import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_native_html_to_pdf/flutter_native_html_to_pdf.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import '../data/local_database.dart';
import '../services/summon_generator_service.dart';
import '../theme/app_theme.dart';

class SummonGeneratorScreen extends StatefulWidget {
  const SummonGeneratorScreen({super.key});

  @override
  State<SummonGeneratorScreen> createState() => _SummonGeneratorScreenState();
}

class _SummonGeneratorScreenState extends State<SummonGeneratorScreen> {
  List<Map<String, Object?>> _pending = [];
  String _selectedDate = 'सभी';
  final _janpad = TextEditingController(text: 'श्रावस्ती');
  bool _autoUpdate = true;
  bool _loading = true;
  bool _generating = false;
  String? _error;
  File? _generatedPdf;
  int _generatedCases = 0;
  int _generatedWitnesses = 0;
  int _updatedStatuses = 0;
  List<String> _skippedStNos = [];

  @override
  void initState() {
    super.initState();
    _loadCases();
  }

  @override
  void dispose() {
    _janpad.dispose();
    super.dispose();
  }

  Future<void> _loadCases() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await LocalDatabase.instance.searchCases('');
      final pending = SummonGeneratorService.pendingCases(all);
      if (!mounted) return;
      setState(() {
        _pending = pending;
        _selectedDate = 'सभी';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'मुकदमों का रिकॉर्ड लोड नहीं हो सका: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> get _availableDates {
    final dates = _pending
        .map((row) => (row['next_hearing'] ?? '').toString().trim())
        .where((date) => date.isNotEmpty)
        .toSet()
        .toList();
    dates.sort((a, b) {
      final da = SummonGeneratorService.parseDate(a);
      final db = SummonGeneratorService.parseDate(b);
      if (da == null && db == null) return a.compareTo(b);
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });
    return ['सभी', ...dates];
  }

  List<Map<String, Object?>> get _selectedRows {
    if (_selectedDate == 'सभी') return _pending;
    return _pending.where((row) =>
      (row['next_hearing'] ?? '').toString().trim() == _selectedDate
    ).toList();
  }

  Future<void> _generatePdf() async {
    if (_generating || _selectedRows.isEmpty) return;
    final janpad = _janpad.text.trim();
    if (janpad.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('जनपद का नाम भरें।')),
      );
      return;
    }

    setState(() => _generating = true);
    try {
      final rows = List<Map<String, Object?>>.from(_selectedRows);
      final result = SummonGeneratorService.generate(rows, janpad: janpad);
      if (result.html == null || result.stNos.isEmpty) {
        setState(() => _skippedStNos = result.skippedStNos);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('चयनित रिकॉर्ड में कोई वैध तलब साक्षी नहीं मिला।')),
        );
        return;
      }

      // Keep generated PDFs inside the existing backed-up case_documents root.
      final appDir = await getApplicationDocumentsDirectory();
      final outputDir = Directory(p.join(appDir.path, 'case_documents', 'summons_generated'));
      await outputDir.create(recursive: true);
      final fileName = 'saman_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}';
      final pdfFile = await HtmlToPdfConverter().convertHtmlToPdf(
        html: result.html!,
        targetDirectory: outputDir.path,
        targetName: fileName,
        pageSize: PdfPageSize.a4.landscape,
      );
      if (!await pdfFile.exists() || await pdfFile.length() < 100) {
        throw StateError('PDF फाइल तैयार नहीं हुई या खाली है।');
      }
      final header = await pdfFile.open();
      final signature = await header.read(4);
      await header.close();
      if (String.fromCharCodes(signature) != '%PDF') {
        throw StateError('तैयार फाइल मान्य PDF नहीं है।');
      }

      var updated = 0;
      final updateErrors = <String>[];
      final generatedStNos = result.stNos.toSet();
      final generatedRows = rows.where((row) =>
        generatedStNos.contains((row['st_no'] ?? '').toString().trim())
      ).toList();

      for (final row in generatedRows) {
        final id = (row['id'] ?? '').toString();
        final stNo = (row['st_no'] ?? '').toString();
        if (id.isEmpty) {
          updateErrors.add(stNo);
          continue;
        }
        try {
          if (_autoUpdate) {
            await LocalDatabase.instance.saveWithAudit(
              table: 'cases',
              values: {'summons_status': 'ISSUED'},
              recordId: id,
              isNew: false,
              action: 'SUMMONS_STATUS_UPDATED',
              module: 'SESSION_COURT',
              details: 'समन PDF बना: ST NO $stNo; $fileName',
            );
            updated++;
          } else {
            await LocalDatabase.instance.logAction(
              'SUMMON_PDF_GENERATED',
              'SESSION_COURT',
              id,
              'ST NO $stNo; $fileName',
            );
          }
        } catch (_) {
          updateErrors.add(stNo);
        }
      }

      if (!mounted) return;
      setState(() {
        _generatedPdf = pdfFile;
        _generatedCases = result.stNos.length;
        _generatedWitnesses = result.witnessCount;
        _updatedStatuses = updated;
        _skippedStNos = result.skippedStNos;
      });
      await _loadCases();

      if (!mounted) return;
      final statusMessage = _autoUpdate
          ? ' $updated केस का सम्मन स्टेटस ISSUED किया गया।'
          : ' केस स्टेटस नहीं बदला गया।';
      final failureMessage = updateErrors.isEmpty
          ? ''
          : ' स्टेटस अपडेट नहीं हुआ: ${updateErrors.join(', ')}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.stNos.length} मुकदमों के ${result.witnessCount} समन की PDF तैयार।$statusMessage$failureMessage',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF नहीं बन सकी: $error')),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<Uint8List?> _pdfBytes() async {
    final file = _generatedPdf;
    if (file == null || !await file.exists()) return null;
    return file.readAsBytes();
  }

  Future<void> _sharePdf() async {
    final bytes = await _pdfBytes();
    if (bytes == null) return;
    await Printing.sharePdf(
      bytes: bytes,
      filename: p.basename(_generatedPdf!.path),
    );
  }

  Future<void> _printPdf() async {
    final bytes = await _pdfBytes();
    if (bytes == null) return;
    await Printing.layoutPdf(
      name: p.basename(_generatedPdf!.path),
      onLayout: (_) async => bytes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedRows = _selectedRows;
    return Scaffold(
      appBar: AppBar(
        title: const Text('समन एवं वारंट जनरेटर'),
        actions: [
          IconButton(
            tooltip: 'रीफ्रेश',
            onPressed: _loading || _generating ? null : _loadCases,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _loadCases,
                          icon: const Icon(Icons.refresh),
                          label: const Text('पुनः प्रयास करें'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppTheme.navy,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.description_rounded, color: Color(0xFFB9D8D2), size: 22),
                              SizedBox(width: 9),
                              Text(
                                'ऑफलाइन समन जनरेशन',
                                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'केवल “बनाना है” स्थिति वाले मुकदमे। एक A4 Landscape पेज पर दो समन।',
                            style: TextStyle(color: Color(0xFFD5DDE8), height: 1.45, fontSize: 12),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(child: _metric('लंबित मुकदमे', _pending.length)),
                              const SizedBox(width: 10),
                              Expanded(child: _metric('चयनित मुकदमे', selectedRows.length)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('जनपद एवं पेशी चयन', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 13),
                            TextField(
                              controller: _janpad,
                              decoration: const InputDecoration(
                                labelText: 'जनपद',
                                prefixIcon: Icon(Icons.location_city_outlined),
                              ),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: _availableDates.contains(_selectedDate) ? _selectedDate : 'सभी',
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'किस तारीख की पेशी का समन बनाएं?',
                                prefixIcon: Icon(Icons.calendar_month_outlined),
                              ),
                              items: _availableDates.map((date) => DropdownMenuItem(
                                value: date,
                                child: Text(date == 'सभी' ? 'सभी तारीखें' : date),
                              )).toList(),
                              onChanged: (value) => setState(() => _selectedDate = value ?? 'सभी'),
                            ),
                            const SizedBox(height: 12),
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              value: _autoUpdate,
                              onChanged: (value) => setState(() => _autoUpdate = value),
                              title: const Text('PDF बनने के बाद स्टेटस ISSUED करें'),
                              subtitle: const Text('बंद रखने पर मुकदमे का सम्मन स्टेटस नहीं बदलेगा।'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(child: Text('समन बनने वाले मुकदमे', style: Theme.of(context).textTheme.titleMedium)),
                        Text('${selectedRows.length} रिकॉर्ड', style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (selectedRows.isEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              const Icon(Icons.check_circle_outline, size: 34, color: AppTheme.teal),
                              const SizedBox(height: 8),
                              const Text('इस चयन में कोई लंबित समन नहीं है'),
                              const SizedBox(height: 4),
                              Text(
                                'मुकदमे के विवरण में “सम्मन की स्थिति” को “बनाना है” चुनें।',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ...selectedRows.map((row) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Container(
                            width: 52,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF0FA),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('ST NO', style: TextStyle(fontSize: 8, color: AppTheme.muted)),
                                Text(
                                  (row['st_no'] ?? '—').toString(),
                                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.navy, fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          title: Text(
                            'राज्य बनाम ${row['accused_name'] ?? '—'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          subtitle: Text(
                            '${row['court_name'] ?? 'न्यायालय नहीं'}  •  ${row['next_hearing'] ?? 'तारीख नहीं'}\n${row['summoned_witnesses'] ?? 'साक्षी विवरण नहीं'}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          isThreeLine: true,
                        ),
                      )),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: selectedRows.isEmpty || _generating ? null : _generatePdf,
                      icon: _generating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.picture_as_pdf_rounded),
                      label: Text(_generating ? 'PDF तैयार हो रही है…' : 'समन PDF तैयार करें'),
                    ),
                    if (_skippedStNos.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'साक्षी विवरण खाली होने के कारण छोड़े गए ST NO: ${_skippedStNos.join(', ')}',
                        style: const TextStyle(color: Color(0xFF9A641B), fontSize: 12),
                      ),
                    ],
                    if (_generatedPdf != null) ...[
                      const SizedBox(height: 18),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.check_circle_rounded, color: AppTheme.teal),
                                  SizedBox(width: 8),
                                  Text('PDF तैयार है', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                ],
                              ),
                              const SizedBox(height: 7),
                              Text(
                                '$_generatedCases मुकदमे • $_generatedWitnesses समन • $_updatedStatuses स्टेटस अपडेट',
                                style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                p.basename(_generatedPdf!.path),
                                style: const TextStyle(fontSize: 11, color: AppTheme.ink),
                              ),
                              const SizedBox(height: 13),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  FilledButton.icon(
                                    onPressed: _printPdf,
                                    icon: const Icon(Icons.print_rounded),
                                    label: const Text('प्रिंट / Save PDF'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _sharePdf,
                                    icon: const Icon(Icons.share_rounded),
                                    label: const Text('PDF शेयर करें'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    const Text(
                      'जारी करने से पहले नाम, न्यायालय, धारा, तारीख और आदेश के शब्दों का मूल अभिलेख से मिलान अवश्य करें।',
                      style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
                    ),
                  ],
                ),
    );
  }

  Widget _metric(String label, int value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$value', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Color(0xFFD5DDE8), fontSize: 11)),
      ],
    ),
  );
}
