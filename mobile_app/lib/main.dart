import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'data/local_database.dart';
import 'screens/cases_screen.dart';
import 'screens/register_screen.dart';
import 'screens/court_documents_screen.dart';
import 'screens/case_activity_screen.dart';
import 'screens/case_preparation_screen.dart';
import 'screens/case_documents_screen.dart';
import 'screens/audit_log_screen.dart';
import 'screens/backup_screen.dart';
import 'screens/global_search_screen.dart';
import 'screens/evidence_screen.dart';
import 'services/secure_backup_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Replace Flutter's opaque red error screen with a readable diagnostic
  // page. This makes device-only startup/build exceptions visible to users.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  ErrorWidget.builder = (details) => Material(
    color: const Color(0xFFF3F6FA),
    child: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Color(0xFFB5473C)),
                const SizedBox(height: 16),
                const Text(
                  'ऐप की स्क्रीन खोलने में त्रुटि हुई',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF172B4D)),
                ),
                const SizedBox(height: 12),
                const Text(
                  'कृपया नीचे दिया गया त्रुटि संदेश सहायता के लिए साझा करें। ऐप का डेटा Clear या Uninstall न करें।',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Color(0xFF68778D)),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5EAF1)),
                  ),
                  child: SelectableText(
                    details.exceptionAsString(),
                    style: const TextStyle(fontSize: 12, color: Color(0xFFAC4038)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  ui.PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught platform error: $error');
    debugPrintStack(stackTrace: stack);
    return true;
  };

  runApp(const CourtCaseManagerApp());
}

class CourtCaseManagerApp extends StatelessWidget {
  const CourtCaseManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'पैरवी रजिस्टर',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // Keep the Navigator/MaterialApp intact. The lock is the home route,
      // not a MaterialApp.builder overlay that can hide route/dialog content.
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

  void _refresh() => setState(() => _counts = LocalDatabase.instance.dashboardCounts());

  void _open(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen)).then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('पैरवी रजिस्टर'),
          Text('कोतवाली भिंगा  •  जनपद श्रावस्ती',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: Colors.white70)),
        ]),
        actions: [
          IconButton(
            onPressed: () => _open(const GlobalSearchScreen()),
            icon: const Icon(Icons.search_rounded),
            tooltip: 'सभी रिकॉर्ड में खोज',
          ),
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded), tooltip: 'रिफ्रेश'),
          const SizedBox(width: 4),
        ],
      ),
      body: FutureBuilder<Map<String, int>>(
        future: _counts,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('डेटाबेस खोलने में समस्या: ${snapshot.error}'),
            ));
          }
          final counts = snapshot.data ?? <String, int>{};
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.navy,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFF263B5C)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.offline_bolt_outlined, size: 14, color: Color(0xFFB9D8D2)),
                            SizedBox(width: 6),
                            Text('ऑफलाइन कार्यप्रणाली',
                              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 17),
                      const Text('न्यायालयीन कार्यवाही\nअब एक ही जगह',
                        style: TextStyle(color: Colors.white, fontSize: 22, height: 1.25, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      const Text('मुकदमे, पेशी, डाक और दस्तावेजों का व्यवस्थित प्रबंधन।',
                        style: TextStyle(color: Color(0xFFD5DDE8), fontSize: 13, height: 1.45)),
                      const SizedBox(height: 16),
                      const Divider(color: Color(0x334B607D), height: 1),
                      const SizedBox(height: 12),
                      const Row(
                        children: [
                          Icon(Icons.shield_outlined, size: 16, color: Color(0xFFB9D8D2)),
                          SizedBox(width: 7),
                          Text('डेटा इसी डिवाइस में सुरक्षित रहता है',
                            style: TextStyle(color: Color(0xFFE8EDF4), fontSize: 11, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _sectionHeading('रजिस्टर का सारांश', 'स्थानीय रिकॉर्ड'),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 560 ? 3 : 2;
                    return GridView.count(
                      crossAxisCount: columns,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: columns == 3 ? 1.9 : 1.72,
                      children: [
                        _StatCard(label: 'कुल मुकदमे', value: counts['cases'] ?? 0, icon: Icons.gavel_rounded, tint: const Color(0xFFEAF0F7), accent: AppTheme.blue),
                        _StatCard(label: 'डाक रजिस्टर', value: counts['dak'] ?? 0, icon: Icons.mark_email_unread_rounded, tint: const Color(0xFFEAF3F1), accent: AppTheme.teal),
                        _StatCard(label: 'रिमांड रजिस्टर', value: counts['remand'] ?? 0, icon: Icons.assignment_turned_in_rounded, tint: const Color(0xFFEAF0F7), accent: AppTheme.blue),
                        _StatCard(label: 'दस्तावेज', value: counts['documents'] ?? 0, icon: Icons.folder_copy_outlined, tint: const Color(0xFFEAF0F7), accent: AppTheme.blue),
                        _StatCard(label: 'संपर्क', value: counts['contacts'] ?? 0, icon: Icons.contacts_outlined, tint: const Color(0xFFEAF3F1), accent: AppTheme.teal),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 25),
                _sectionHeading('मुख्य कार्य', 'रजिस्टर और सुविधाएँ'),
                const SizedBox(height: 12),
                _ModuleTile(
                  icon: Icons.search_rounded,
                  title: 'सभी रिकॉर्ड में खोज',
                  subtitle: 'मुकदमे, डाक, रिमांड, संपर्क और दस्तावेज एक साथ खोजें',
                  color: AppTheme.teal,
                  onTap: () => _open(const GlobalSearchScreen()),
                ),
                _ModuleTile(icon: Icons.account_balance_rounded, title: 'सेशन कोर्ट', subtitle: 'मुकदमे, पेशी, गवाह और स्थिति', color: AppTheme.blue, onTap: () => _open(const CasesScreen())),
                _ModuleTile(icon: Icons.mark_email_unread_rounded, title: 'डाक रजिस्टर', subtitle: 'डाक प्रविष्टि, स्थिति और खोज', color: AppTheme.teal, onTap: () => _open(const RegisterScreen(config: dakConfig))),
                _ModuleTile(icon: Icons.assignment_rounded, title: 'रिमांड रजिस्टर', subtitle: 'रिमांड संबंधी विवरण', color: AppTheme.blue, onTap: () => _open(const RegisterScreen(config: remandConfig))),
                _ModuleTile(icon: Icons.contact_phone_rounded, title: 'Address Book', subtitle: 'अधिकारी, गवाह और विभागीय संपर्क', color: AppTheme.teal, onTap: () => _open(const RegisterScreen(config: addressConfig))),
                _ModuleTile(icon: Icons.description_rounded, title: 'समन एवं कार्यवाही आख्या', subtitle: 'मुकदमे के आधार पर प्रारूप तैयार करें', color: AppTheme.blue, onTap: () => _open(const CourtDocumentsScreen())),
                _ModuleTile(icon: Icons.timeline_rounded, title: 'Timeline एवं Checklist', subtitle: 'तारीखवार कार्यवाही और लंबित काम', color: AppTheme.teal, onTap: () => _open(const CaseActivityScreen())),
                _ModuleTile(icon: Icons.event_available_rounded, title: 'अगली पेशी की तैयारी', subtitle: 'आगामी पेशी, लंबित कार्य और तैयारी का सारांश', color: AppTheme.blue, onTap: () => _open(const CasePreparationScreen())),
                _ModuleTile(icon: Icons.folder_copy_rounded, title: 'दस्तावेज लाइब्रेरी', subtitle: 'केस फाइलें और पुराने संस्करण', color: AppTheme.teal, onTap: () => _open(const CaseDocumentsScreen())),
                _ModuleTile(
                  icon: Icons.inventory_2_outlined,
                  title: 'Evidence एवं Exhibit Manager',
                  subtitle: 'बरामदगी, मालखाना, सील, Exhibit और संलग्न फाइलें',
                  color: AppTheme.teal,
                  onTap: () => _open(const EvidenceScreen()),
                ),
                _ModuleTile(icon: Icons.security_rounded, title: 'Audit Log', subtitle: 'ऐप में दर्ज गतिविधियों का रिकॉर्ड', color: AppTheme.blue, onTap: () => _open(const AuditLogScreen())),
                const SizedBox(height: 18),
                _sectionHeading('सुरक्षा एवं बैकअप', 'डिवाइस प्रबंधन'),
                const SizedBox(height: 12),
                _UtilityTile(icon: Icons.enhanced_encryption_rounded, title: 'Backup & Restore', onTap: () => _open(const BackupScreen())),
                const SizedBox(height: 18),
                const Center(child: Text('पैरवी रजिस्टर  •  Offline Case Manager',
                  style: TextStyle(color: Color(0xFF8995A7), fontSize: 11, fontWeight: FontWeight.w600))),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _sectionHeading(String title, String subtitle) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ])),
    ],
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.icon, required this.tint, required this.accent});
  final String label;
  final int value;
  final IconData icon;
  final Color tint;
  final Color accent;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(13),
      child: Row(children: [
        Container(width: 42, height: 42,
          decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(13)),
          child: Icon(icon, color: accent, size: 21)),
        const SizedBox(width: 11),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('$value', style: TextStyle(fontSize: 23, height: 1.1, fontWeight: FontWeight.w800, color: accent)),
          const SizedBox(height: 4),
          Text(label, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Color(0xFF68778D), fontWeight: FontWeight.w600)),
        ])),
      ]),
    ),
  );
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({required this.icon, required this.title, required this.subtitle, required this.color, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE5EAF1))),
          child: Row(children: [
            Container(width: 44, height: 44,
              decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color, size: 22)),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF172B4D))),
              const SizedBox(height: 3),
              Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF68778D))),
            ])),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF9AA6B6)),
          ]),
        ),
      ),
    ),
  );
}

class _UtilityTile extends StatelessWidget {
  const _UtilityTile({required this.icon, required this.title, required this.onTap});
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE5EAF1))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: AppTheme.blue, size: 23),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        ]),
      ),
    ),
  );
}
