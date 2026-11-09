import 'package:flutter/material.dart';
import 'data/local_database.dart';
import 'screens/cases_screen.dart';
import 'screens/register_screen.dart';
import 'screens/court_documents_screen.dart';
import 'screens/case_activity_screen.dart';
import 'screens/case_documents_screen.dart';
import 'screens/audit_log_screen.dart';
import 'screens/backup_screen.dart';
import 'screens/change_pin_screen.dart';
import 'services/app_lock_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalDatabase.instance.database;
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
      builder: (context, child) => AppLockGate(child: child ?? const SizedBox.shrink()),
      home: const HomeScreen(),
    );
  }
}


class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});
  final Widget child;
  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _ready = false;
  bool _configured = false;
  bool _unlocked = false;
  bool _busy = false;
  bool _showPin = false;
  bool _showConfirm = false;
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
      if (_unlocked && mounted) {
        setState(() {
          _unlocked = false;
          _pin.clear();
          _confirm.clear();
          _error = null;
          _showPin = false;
          _showConfirm = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    if (!RegExp(r'^\\d{6,8}$').hasMatch(_pin.text)) {
      setState(() => _error = 'PIN में 6 से 8 अंक होने चाहिए।');
      return;
    }
    if (!_configured && _pin.text != _confirm.text) {
      setState(() => _error = 'दोनों PIN एक जैसे नहीं हैं।');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      if (!_configured) {
        await AppLockService.instance.setPin(_pin.text);
        _configured = true;
      } else {
        final valid = await AppLockService.instance.verifyPin(_pin.text);
        if (!valid) {
          if (mounted) setState(() => _error = 'PIN सही नहीं है। कृपया फिर से प्रयास करें।');
          return;
        }
      }
      if (mounted) {
        setState(() {
          _unlocked = true;
          _pin.clear();
          _confirm.clear();
          _showPin = false;
          _showConfirm = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        backgroundColor: AppTheme.canvas,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final setup = !_configured;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!_unlocked)
          Scaffold(
            backgroundColor: AppTheme.canvas,
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(22),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 410),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 66,
                              height: 66,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEAF0F7),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Icon(
                                setup ? Icons.shield_outlined : Icons.lock_outline_rounded,
                                size: 32,
                                color: AppTheme.blue,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              setup ? 'ऐप सुरक्षा PIN बनाएं' : 'पैरवी रजिस्टर अनलॉक करें',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              setup
                                  ? 'पहली बार उपयोग से पहले 6 से 8 अंकों का PIN बनाएं।'
                                  : 'अपना सुरक्षा PIN डालकर ऐप खोलें।',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 24),
                            TextField(
                              controller: _pin,
                              obscureText: !_showPin,
                              keyboardType: TextInputType.number,
                              textInputAction: setup ? TextInputAction.next : TextInputAction.done,
                              maxLength: 8,
                              onSubmitted: (_) { if (!setup) _submit(); },
                              decoration: InputDecoration(
                                labelText: setup ? 'नया PIN (6–8 अंक)' : 'सुरक्षा PIN',
                                counterText: '',
                                prefixIcon: const Icon(Icons.password_rounded),
                                suffixIcon: IconButton(
                                  tooltip: _showPin ? 'PIN छिपाएँ' : 'PIN दिखाएँ',
                                  onPressed: () => setState(() => _showPin = !_showPin),
                                  icon: Icon(_showPin ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                                ),
                              ),
                            ),
                            if (setup) ...[
                              const SizedBox(height: 13),
                              TextField(
                                controller: _confirm,
                                obscureText: !_showConfirm,
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.done,
                                maxLength: 8,
                                onSubmitted: (_) => _submit(),
                                decoration: InputDecoration(
                                  labelText: 'PIN दोबारा डालें',
                                  counterText: '',
                                  prefixIcon: const Icon(Icons.verified_user_outlined),
                                  suffixIcon: IconButton(
                                    tooltip: _showConfirm ? 'PIN छिपाएँ' : 'PIN दिखाएँ',
                                    onPressed: () => setState(() => _showConfirm = !_showConfirm),
                                    icon: Icon(_showConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                                  ),
                                ),
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFEFED),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFF1D2CE)),
                                ),
                                child: Text(_error!,
                                  style: const TextStyle(color: Color(0xFFAC4038), fontSize: 12, height: 1.4)),
                              ),
                            ],
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              height: 49,
                              child: FilledButton(
                                onPressed: _busy ? null : _submit,
                                child: _busy
                                    ? const SizedBox(width: 19, height: 19,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : Text(setup ? 'PIN सेट करें' : 'ऐप अनलॉक करें'),
                              ),
                            ),
                            if (setup) ...[
                              const SizedBox(height: 14),
                              const Text(
                                'PIN सुरक्षित रखें। इसे भूलने पर ऐप में bypass उपलब्ध नहीं है।',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 11, height: 1.4, color: AppTheme.muted),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
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
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [Color(0xFF14233F), Color(0xFF315E9E), Color(0xFF287E86)],
                    ),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: const [BoxShadow(color: Color(0x22315E9E), blurRadius: 18, offset: Offset(0, 8))],
                  ),
                  child: Stack(children: [
                    const Positioned(right: 0, top: 0, child: Icon(Icons.account_balance_outlined, size: 76, color: Color(0x22FFFFFF))),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(30)),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.offline_bolt_rounded, size: 14, color: Color(0xFF9EF0D0)),
                          SizedBox(width: 5),
                          Text('OFFLINE • LOCAL DATA', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .8)),
                        ]),
                      ),
                      const SizedBox(height: 16),
                      const Text('न्यायालयीन कार्यवाही\nअब एक ही जगह',
                        style: TextStyle(color: Colors.white, fontSize: 23, height: 1.22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      const Text('मुकदमे, पेशी, डाक और दस्तावेजों का व्यवस्थित प्रबंधन।',
                        style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
                      const SizedBox(height: 15),
                      Row(children: [
                        const Icon(Icons.shield_outlined, size: 16, color: Color(0xFFB8F1DD)),
                        const SizedBox(width: 6),
                        const Text('डेटा इसी डिवाइस में सुरक्षित रहता है',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                      ]),
                    ]),
                  ]),
                ),
                const SizedBox(height: 24),
                _sectionHeading('रजिस्टर का सारांश', 'स्थानीय रिकॉर्ड'),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 2, shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.72,
                  children: [
                    _StatCard(label: 'कुल मुकदमे', value: counts['cases'] ?? 0, icon: Icons.gavel_rounded, tint: const Color(0xFFEAF0FF), accent: const Color(0xFF315E9E)),
                    _StatCard(label: 'डाक रजिस्टर', value: counts['dak'] ?? 0, icon: Icons.mark_email_unread_rounded, tint: const Color(0xFFE5F5F2), accent: const Color(0xFF168C83)),
                    _StatCard(label: 'रिमांड रजिस्टर', value: counts['remand'] ?? 0, icon: Icons.assignment_turned_in_rounded, tint: const Color(0xFFFFF2E5), accent: const Color(0xFFC47B28)),
                    _StatCard(label: 'दस्तावेज', value: counts['documents'] ?? 0, icon: Icons.folder_copy_rounded, tint: const Color(0xFFF1ECFF), accent: const Color(0xFF7655B5)),
                    _StatCard(label: 'संपर्क', value: counts['contacts'] ?? 0, icon: Icons.contacts_rounded, tint: const Color(0xFFFFEDEF), accent: const Color(0xFFB64F66)),
                  ],
                ),
                const SizedBox(height: 25),
                _sectionHeading('मुख्य कार्य', 'रजिस्टर और सुविधाएँ'),
                const SizedBox(height: 12),
                _ModuleTile(icon: Icons.account_balance_rounded, title: 'सेशन कोर्ट', subtitle: 'मुकदमे, पेशी, गवाह और स्थिति', color: const Color(0xFF315E9E), onTap: () => _open(const CasesScreen())),
                _ModuleTile(icon: Icons.mark_email_unread_rounded, title: 'डाक रजिस्टर', subtitle: 'डाक प्रविष्टि, स्थिति और खोज', color: const Color(0xFF168C83), onTap: () => _open(const RegisterScreen(config: dakConfig))),
                _ModuleTile(icon: Icons.assignment_rounded, title: 'रिमांड रजिस्टर', subtitle: 'रिमांड संबंधी विवरण', color: const Color(0xFFC47B28), onTap: () => _open(const RegisterScreen(config: remandConfig))),
                _ModuleTile(icon: Icons.contact_phone_rounded, title: 'Address Book', subtitle: 'अधिकारी, गवाह और विभागीय संपर्क', color: const Color(0xFF7655B5), onTap: () => _open(const RegisterScreen(config: addressConfig))),
                _ModuleTile(icon: Icons.description_rounded, title: 'समन एवं कार्यवाही आख्या', subtitle: 'मुकदमे के आधार पर प्रारूप तैयार करें', color: const Color(0xFF315E9E), onTap: () => _open(const CourtDocumentsScreen())),
                _ModuleTile(icon: Icons.timeline_rounded, title: 'Timeline एवं Checklist', subtitle: 'तारीखवार कार्यवाही और लंबित काम', color: const Color(0xFF168C83), onTap: () => _open(const CaseActivityScreen())),
                _ModuleTile(icon: Icons.folder_copy_rounded, title: 'दस्तावेज लाइब्रेरी', subtitle: 'केस फाइलें और पुराने संस्करण', color: const Color(0xFF7655B5), onTap: () => _open(const CaseDocumentsScreen())),
                _ModuleTile(icon: Icons.security_rounded, title: 'Audit Log', subtitle: 'ऐप में दर्ज गतिविधियों का रिकॉर्ड', color: const Color(0xFFB06B2A), onTap: () => _open(const AuditLogScreen())),
                const SizedBox(height: 18),
                _sectionHeading('सुरक्षा एवं बैकअप', 'डिवाइस प्रबंधन'),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _UtilityTile(icon: Icons.enhanced_encryption_rounded, title: 'Backup & Restore', onTap: () => _open(const BackupScreen()))),
                  const SizedBox(width: 10),
                  Expanded(child: _UtilityTile(icon: Icons.password_rounded, title: 'PIN बदलें', onTap: () => _open(const ChangePinScreen()))),
                ]),
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
          Icon(icon, color: const Color(0xFF315E9E), size: 23),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        ]),
      ),
    ),
  );
}
