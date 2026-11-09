import 'package:flutter/material.dart';

import '../data/local_database.dart';
import '../theme/app_theme.dart';

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  final _searchController = TextEditingController();
  late Future<List<Map<String, Object?>>> _entries;
  String _query = '';
  String _module = 'सभी';

  @override
  void initState() {
    super.initState();
    _entries = LocalDatabase.instance.auditEntries();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final future = LocalDatabase.instance.auditEntries();
    setState(() => _entries = future);
    await future;
  }

  String _value(Map<String, Object?> row, String key) {
    final value = row[key]?.toString().trim() ?? '';
    return value.isEmpty || value == 'null' ? '—' : value;
  }

  String _date(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value == '—' ? 'समय उपलब्ध नहीं' : value;
    final d = parsed.toLocal();
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    final hour = (d.hour % 12 == 0 ? 12 : d.hour % 12).toString().padLeft(2, '0');
    final minute = d.minute.toString().padLeft(2, '0');
    return day + '-' + month + '-' + d.year.toString() + '  ' + hour + ':' + minute + (d.hour >= 12 ? ' PM' : ' AM');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('गतिविधि लॉग'),
        actions: [
          IconButton(
            tooltip: 'रीफ्रेश',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _entries,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'लॉग लोड नहीं हो सका',
              subtitle: 'कृपया दोबारा प्रयास करें।',
              action: FilledButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('फिर प्रयास करें'),
              ),
            );
          }

          final rows = snapshot.data ?? [];
          final modules = rows.map((r) => _value(r, 'module'))
              .where((v) => v != '—').toSet().toList()..sort();
          final filters = ['सभी', ...modules];
          final q = _query.toLowerCase();
          final visible = rows.where((r) {
            if (_module != 'सभी' && _value(r, 'module') != _module) return false;
            if (q.isEmpty) return true;
            return [
              _value(r, 'action'),
              _value(r, 'module'),
              _value(r, 'record_id'),
              _value(r, 'details'),
              _value(r, 'created_at'),
            ].join(' ').toLowerCase().contains(q);
          }).toList();

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                Container(
                  padding: const EdgeInsets.all(17),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF0F6),
                    border: Border.all(color: const Color(0xFFDCE5EF)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.manage_history_rounded, color: AppTheme.ink),
                      ),
                      const SizedBox(width: 13),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ऑडिट ट्रेल', style: TextStyle(color: AppTheme.ink, fontSize: 16, fontWeight: FontWeight.w700)),
                            SizedBox(height: 3),
                            Text('डिवाइस पर दर्ज गतिविधियों का विवरण', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(rows.length.toString(), style: const TextStyle(color: AppTheme.ink, fontSize: 23, fontWeight: FontWeight.w800)),
                          const Text('कुल रिकॉर्ड', style: TextStyle(color: AppTheme.muted, fontSize: 10)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v.trim()),
                  decoration: InputDecoration(
                    hintText: 'गतिविधि, मॉड्यूल या रिकॉर्ड खोजें',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty ? null : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ),
                if (filters.length > 2) ...[
                  const SizedBox(height: 15),
                  const Text('मॉड्यूल के अनुसार', style: TextStyle(color: AppTheme.muted, fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 38,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: filters.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final value = filters[index];
                        final selected = value == _module;
                        return ChoiceChip(
                          label: Text(value),
                          selected: selected,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _module = value),
                          selectedColor: AppTheme.blue,
                          backgroundColor: Colors.white,
                          side: BorderSide(color: selected ? AppTheme.blue : AppTheme.line),
                          labelStyle: TextStyle(color: selected ? Colors.white : AppTheme.ink, fontSize: 12, fontWeight: FontWeight.w600),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 17),
                Row(
                  children: [
                    Text('हाल की गतिविधियाँ', style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    Text(visible.length.toString() + ' प्रविष्टियाँ', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: 10),
                if (visible.isEmpty)
                  _EmptyState(
                    icon: rows.isEmpty ? Icons.history_rounded : Icons.search_off_rounded,
                    title: rows.isEmpty ? 'अभी कोई गतिविधि दर्ज नहीं है' : 'कोई परिणाम नहीं मिला',
                    subtitle: rows.isEmpty ? 'ऐप में किए गए बदलाव यहाँ दिखाई देंगे।' : 'खोज शब्द या चुना हुआ मॉड्यूल बदलकर देखें।',
                  )
                else
                  ...visible.map((row) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AuditCard(
                      action: _value(row, 'action'),
                      module: _value(row, 'module'),
                      recordId: _value(row, 'record_id'),
                      details: _value(row, 'details'),
                      date: _date(_value(row, 'created_at')),
                    ),
                  )),
                const SizedBox(height: 8),
                const Text('यह लॉग इसी डिवाइस पर सुरक्षित गतिविधियों का रिकॉर्ड है।', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.muted, fontSize: 11)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AuditCard extends StatelessWidget {
  const _AuditCard({required this.action, required this.module, required this.recordId, required this.details, required this.date});

  final String action;
  final String module;
  final String recordId;
  final String details;
  final String date;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: const Color(0xFFEAF0F6), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.history_rounded, size: 19, color: AppTheme.ink),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(action, style: const TextStyle(color: AppTheme.ink, fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 7,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFFF1F4F7), borderRadius: BorderRadius.circular(20)),
                        child: Text(module, style: const TextStyle(color: AppTheme.ink, fontSize: 10, fontWeight: FontWeight.w600)),
                      ),
                      Text('रिकॉर्ड: ' + recordId, style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
                    ],
                  ),
                  if (details != '—') ...[
                    const SizedBox(height: 9),
                    Text(details, style: const TextStyle(color: AppTheme.ink, fontSize: 13, height: 1.4)),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.schedule_rounded, size: 13, color: AppTheme.muted),
                      const SizedBox(width: 5),
                      Expanded(child: Text(date, style: const TextStyle(color: AppTheme.muted, fontSize: 11))),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.subtitle, this.action});

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 38, color: AppTheme.muted),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.ink, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}
