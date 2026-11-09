import 'package:flutter/material.dart';
import '../data/local_database.dart';

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});
  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  late Future<List<Map<String, Object?>>> _entries;
  @override
  void initState() { super.initState(); _entries = LocalDatabase.instance.auditEntries(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Audit Log')),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: _entries,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('लॉग लोड नहीं हुआ: ${snapshot.error}'));
        final rows = snapshot.data ?? [];
        if (rows.isEmpty) return const Center(child: Text('अभी कोई गतिविधि दर्ज नहीं है।'));
        return RefreshIndicator(
          onRefresh: () async => setState(() { _entries = LocalDatabase.instance.auditEntries(); }),
          child: ListView.builder(
            padding: const EdgeInsets.all(12), itemCount: rows.length,
            itemBuilder: (_, i) {
              final r = rows[i];
              return Card(child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.history)),
                title: Text(r['action'].toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${r['module']} • Record: ${r['record_id']}\n${r['details']}\n${r['created_at']}'),
                isThreeLine: true,
              ));
            },
          ),
        );
      },
    ),
  );
}
