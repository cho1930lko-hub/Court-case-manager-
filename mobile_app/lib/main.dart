import 'package:flutter/material.dart';
import 'data/local_database.dart';
import 'screens/cases_screen.dart';
import 'screens/register_screen.dart';
import 'screens/court_documents_screen.dart';
import 'screens/case_activity_screen.dart';
import 'screens/case_documents_screen.dart';
import 'screens/audit_log_screen.dart';
import 'screens/backup_screen.dart';
import 'services/app_lock_service.dart';

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
      home: const AppLockGate(),
    );
  }
}


class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key});
  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _ready = false;
  bool _configured = false;
  bool _unlocked = false;
  bool _busy = false;
  String? _error;
  final _pin = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkSetup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _checkSetup() async {
    final configured = await AppLockService.instance.isConfigured;
    if (!mounted) return;
    setState(() { _configured = configured; _ready = true; });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_unlocked && mounted) setState(() { _unlocked = false; _pin.clear(); });
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      if (!_configured) {
        if (_pin.text != _confirm.text) {
          setState(() => _error = 'दोनों PIN एक जैसे नहीं हैं।');
          return;
        }
        await AppLockService.instance.setPin(_pin.text);
        _configured = true;
      } else {
        final valid = await AppLockService.instance.verifyPin(_pin.text);
        if (!valid) {
          setState(() => _error = 'गलत PIN। कृपया फिर से प्रयास करें।');
          return;
        }
      }
      if (mounted) setState(() { _unlocked = true; _pin.clear(); _confirm.clear(); });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_unlocked) return const HomeScreen();
    final setup = !_configured;
    return Scaffold(
      body: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock_outline, size: 54, color: Color(0xFF3158B7)),
              const SizedBox(height: 14),
              Text(setup ? 'ऐप सुरक्षा PIN बनाएं' : 'पैरवी रजिस्टर अनलॉक करें',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(setup ? 'पहली बार उपयोग से पहले 6 से 8 अंकों का PIN बनाएं।' : 'अपना PIN डालकर ऐप खोलें।',
                textAlign: TextAlign.center),
              const SizedBox(height: 18),
              TextField(controller: _pin, obscureText: true, keyboardType: TextInputType.number,
                maxLength: 8, decoration: const InputDecoration(labelText: 'PIN', border: OutlineInputBorder())),
              if (setup) ...[
                const SizedBox(height: 8),
                TextField(controller: _confirm, obscureText: true, keyboardType: TextInputType.number,
                  maxLength: 8, decoration: const InputDecoration(labelText: 'PIN दोबारा डालें', border: OutlineInputBorder())),
              ],
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.red))),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) :
                  Text(setup ? 'PIN सेट करें' : 'अनलॉक करें'),
              )),
            ]),
          )),
        ),
      )),
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
                  _StatCard(label: 'संपर्क', value: counts['contacts']!, icon: Icons.contacts),
                ],
              ),
              const SizedBox(height: 18),
              const Text('मुख्य मॉड्यूल', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              _ModuleTile(icon: Icons.folder_open, title: 'सेशन कोर्ट', subtitle: 'मुकदमे, पेशी, गवाह और स्थिति', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CasesScreen())).then((_) => _refresh())),
              _ModuleTile(icon: Icons.mark_email_unread, title: 'Dak Register', subtitle: 'डाक प्रविष्टि और खोज', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen(config: dakConfig))).then((_) => _refresh())),
              _ModuleTile(icon: Icons.assignment, title: 'Rimand Register', subtitle: 'रिमांड का रिकॉर्ड', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen(config: remandConfig))).then((_) => _refresh())),
              _ModuleTile(icon: Icons.contacts, title: 'Address Book', subtitle: 'संपर्क और विभाग', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen(config: addressConfig))).then((_) => _refresh())),
              _ModuleTile(icon: Icons.description, title: 'समन एवं कार्यवाही आख्या', subtitle: 'मुकदमे से जुड़ा ड्राफ्ट तैयार करें', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CourtDocumentsScreen()))),
              _ModuleTile(icon: Icons.timeline, title: 'Case Timeline & Checklist', subtitle: 'तारीखवार कार्यवाही और लंबित कार्य', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CaseActivityScreen()))),
              _ModuleTile(icon: Icons.folder_copy, title: 'Case Document Library', subtitle: 'मुकदमे की फाइलें और पुराने संस्करण', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CaseDocumentsScreen()))),
              _ModuleTile(icon: Icons.security, title: 'Audit Log', subtitle: 'ऐप में दर्ज बदलावों का रिकॉर्ड', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuditLogScreen()))),
              _ModuleTile(icon: Icons.backup, title: 'Backup & Restore', subtitle: 'AES-256-GCM encrypted backup और restore', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupScreen()))),
              const SizedBox(height: 12),
              const Text('मुकदमे की कार्यवाही, चेकलिस्ट और दस्तावेज़ अब स्थानीय रूप से दर्ज किए जा सकते हैं.',
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
