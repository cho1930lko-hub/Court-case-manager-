import 'package:flutter/material.dart';
import 'data/local_database.dart';
import 'screens/cases_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalDatabase.instance.database;
  runApp(const CourtCaseManagerApp());
}

class CourtCaseManagerApp extends StatelessWidget {
  const CourtCaseManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF1E2A4A);
    return MaterialApp(
      title: 'पैरवी रजिस्टर',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4169E1)),
        scaffoldBackgroundColor: const Color(0xFFF4F6FB),
        appBarTheme: const AppBarTheme(
          backgroundColor: navy,
          foregroundColor: Colors.white,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          elevation: 1,
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<Map<String, int>> _counts;

  @override
  void initState() {
    super.initState();
    _counts = LocalDatabase.instance.dashboardCounts();
  }

  void _refresh() {
    setState(() => _counts = LocalDatabase.instance.dashboardCounts());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('⚖️ पैरवी रजिस्टर', style: TextStyle(fontWeight: FontWeight.w700)),
            Text('कोतवाली भिंगा, जनपद श्रावस्ती',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400)),
          ],
        ),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
        ],
      ),
      body: FutureBuilder<Map<String, int>>(
        future: _counts,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Database error: ${snapshot.error}'));
          }
          final counts = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF263B68), Color(0xFF4169E1)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('आपका Offline Case Manager',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    SizedBox(height: 6),
                    Text('डेटा इसी मोबाइल में सेव होगा। इंटरनेट या Google Sheets की जरूरत नहीं।',
                        style: TextStyle(color: Colors.white70)),
                    SizedBox(height: 12),
                    Row(children: [
                      Icon(Icons.offline_bolt, color: Colors.lightGreenAccent, size: 18),
                      SizedBox(width: 6),
                      Text('Local Database तैयार', style: TextStyle(color: Colors.white)),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text('रजिस्टर सारांश', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.7,
                children: [
                  _StatCard(label: 'कुल मुकदमे', value: counts['cases']!, icon: Icons.gavel),
                  _StatCard(label: 'Dak Register', value: counts['dak']!, icon: Icons.markunread_mailbox),
                  _StatCard(label: 'Rimand Register', value: counts['remand']!, icon: Icons.assignment),
                  _StatCard(label: 'दस्तावेज', value: counts['documents']!, icon: Icons.folder),
                ],
              ),
              const SizedBox(height: 18),
              const Text('मुख्य मॉड्यूल', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              _ModuleTile(icon: Icons.folder_open, title: 'सेशन कोर्ट', subtitle: 'मुकदमे, पेशी, गवाह और स्थिति', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CasesScreen()))),
              const _ModuleTile(icon: Icons.mark_email_unread, title: 'Dak Register', subtitle: 'डाक प्रविष्टि और फोटो'),
              const _ModuleTile(icon: Icons.assignment, title: 'Rimand Register', subtitle: 'रिमांड का रिकॉर्ड'),
              const _ModuleTile(icon: Icons.contacts, title: 'Address Book', subtitle: 'संपर्क और विभाग'),
              const _ModuleTile(icon: Icons.history, title: 'Case Timeline & Checklist', subtitle: 'कार्यवाही का इतिहास और लंबित कार्य'),
              const _ModuleTile(icon: Icons.backup, title: 'Backup & Export', subtitle: 'Excel और सुरक्षित ZIP बैकअप'),
              const SizedBox(height: 12),
              const Text('प्रारंभिक आधार तैयार है। अगले चरण में रिकॉर्ड जोड़ने, संपादित करने, खोजने और बैकअप की स्क्रीन जोड़ी जाएँगी.',
                  style: TextStyle(color: Colors.black54)),
            ],
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.icon});
  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: const Color(0xFF4169E1)),
          const SizedBox(height: 8),
          Text('$value', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12)),
        ],
      ),
    ),
  );
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({required this.icon, required this.title, required this.subtitle, this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFEAF0FF),
        child: Icon(icon, color: const Color(0xFF3158B7)),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap ?? () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$title मॉड्यूल अगले विकास चरण में जोड़ा जाएगा।')),
      ),
    ),
  );
}
