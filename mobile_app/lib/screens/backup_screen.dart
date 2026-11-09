import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/secure_backup_service.dart';
import '../theme/app_theme.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _working = false;
  String _workingLabel = '';

  Future<String?> _askPassword({required String title}) async {
    final controller = TextEditingController();
    bool obscure = true;
    String? validationError;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: !_working,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Backup को सुरक्षित रखने और खोलने के लिए यही password इस्तेमाल होगा।',
                style: TextStyle(color: AppTheme.muted, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: controller,
                obscureText: obscure,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) {
                  if (validationError != null) {
                    setDialogState(() => validationError = null);
                  }
                },
                decoration: InputDecoration(
                  labelText: 'Backup password',
                  hintText: 'कम से कम 12 अक्षर',
                  errorText: validationError,
                  suffixIcon: IconButton(
                    tooltip: obscure ? 'Password दिखाएँ' : 'Password छिपाएँ',
                    onPressed: () => setDialogState(() => obscure = !obscure),
                    icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 15, color: AppTheme.muted),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Password भूलने पर encrypted backup वापस नहीं खोला जा सकेगा।',
                      style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.35),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('रद्द करें'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.length < 12) {
                  setDialogState(() => validationError = 'Password कम से कम 12 अक्षरों का रखें।');
                  return;
                }
                Navigator.pop(dialogContext, controller.text);
              },
              child: const Text('आगे बढ़ें'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFF8C3B36) : AppTheme.ink,
      ));
  }

  Future<void> _createBackup() async {
    final password = await _askPassword(title: 'Encrypted Backup बनाएं');
    if (password == null || !mounted) return;

    setState(() {
      _working = true;
      _workingLabel = 'Backup तैयार किया जा रहा है…';
    });
    try {
      final bytes = await SecureBackupService.instance.createBackup(password);
      if (!mounted) return;
      setState(() => _workingLabel = 'फ़ाइल सेव करने के लिए स्थान चुनें…');
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Encrypted backup सेव करें',
        fileName: 'court_case_manager_backup.ccmbak',
        bytes: bytes,
      );
      if (!mounted) return;
      _showMessage(path == null
          ? 'Backup सेव करना रद्द किया गया।'
          : 'Encrypted backup सफलतापूर्वक सेव हो गया।');
    } catch (e) {
      _showMessage('Backup असफल: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _workingLabel = '';
        });
      }
    }
  }

  Future<void> _restoreBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore से पहले ध्यान दें'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Restore करने पर इस मोबाइल का मौजूदा डेटाबेस और Case Documents चुने गए backup से बदल जाएंगे।',
              style: TextStyle(height: 1.45),
            ),
            SizedBox(height: 12),
            Text(
              'आगे बढ़ने से पहले वर्तमान डेटा का अलग backup बना लें। यह प्रक्रिया पूरी होने तक ऐप बंद न करें।',
              style: TextStyle(color: Color(0xFF8C3B36), fontSize: 12, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('अभी नहीं'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('समझ गया, आगे बढ़ें'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ccmbak'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty || picked.files.single.bytes == null) return;

    final password = await _askPassword(title: 'Backup password डालें');
    if (password == null || !mounted) return;

    setState(() {
      _working = true;
      _workingLabel = 'Backup की जाँच और Restore चल रहा है…';
    });
    try {
      await SecureBackupService.instance.restoreBackup(picked.files.single.bytes!, password);
      if (!mounted) return;
      _showMessage('Restore पूरा हुआ। कृपया ऐप बंद करके दोबारा खोलें।');
    } catch (e) {
      _showMessage('Restore असफल: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _workingLabel = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: Stack(
        children: [
          ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF0F6),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFDCE5EF)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.shield_outlined, color: AppTheme.ink, size: 23),
                    ),
                    const SizedBox(width: 13),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'आपके डेटा की सुरक्षित कॉपी',
                            style: TextStyle(color: AppTheme.ink, fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          SizedBox(height: 5),
                          Text(
                            'डेटाबेस और ऐप के Case Documents को password-protected backup में रखा जाता है।',
                            style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.45),
                          ),
                          SizedBox(height: 9),
                          Row(
                            children: [
                              Icon(Icons.lock_outline_rounded, size: 14, color: AppTheme.muted),
                              SizedBox(width: 6),
                              Text(
                                'AES-256-GCM encryption',
                                style: TextStyle(color: AppTheme.ink, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'BACKUP',
                style: TextStyle(color: AppTheme.muted, fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 9),
              _ActionCard(
                icon: Icons.backup_outlined,
                title: 'नया Backup बनाएं',
                description: 'डेटाबेस और दस्तावेज़ों की encrypted कॉपी फ़ाइल में सेव करें।',
                buttonLabel: 'Backup बनाएं',
                onPressed: _working ? null : _createBackup,
                primary: true,
              ),
              const SizedBox(height: 18),
              const Text(
                'RESTORE',
                style: TextStyle(color: AppTheme.muted, fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 9),
              _ActionCard(
                icon: Icons.settings_backup_restore_rounded,
                title: 'Backup से Restore करें',
                description: 'पहले से सेव की गई .ccmbak फ़ाइल से डेटा वापस लाएँ।',
                buttonLabel: 'फ़ाइल चुनें',
                onPressed: _working ? null : _restoreBackup,
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFEADCB9)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Color(0xFF8A641E), size: 19),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Backup password सुरक्षित रखें। इसे भूलने पर backup नहीं खोला जा सकेगा। Restore मौजूदा डेटा को बदलता है; पहले अलग backup अवश्य बना लें।',
                        style: TextStyle(color: Color(0xFF66552F), fontSize: 12, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 13),
              const Text(
                'सावधानी: SQLCipher migration, secure key storage, App Lock और Backup/Restore का वास्तविक Android मोबाइल पर परीक्षण अभी बाकी है। परीक्षण पूरा होने तक वास्तविक पुलिस/न्यायालय रिकॉर्ड दर्ज न करें।',
                style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.45),
              ),
            ],
          ),
          if (_working)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.28),
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 32),
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 15),
                        Text(
                          _workingLabel,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'कृपया ऐप बंद न करें।',
                          style: TextStyle(color: AppTheme.muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onPressed,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF0F6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: AppTheme.ink, size: 20),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(color: AppTheme.ink, fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              description,
              style: const TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: primary
                  ? FilledButton.icon(
                      onPressed: onPressed,
                      icon: const Icon(Icons.backup_outlined),
                      label: Text(buttonLabel),
                    )
                  : OutlinedButton.icon(
                      onPressed: onPressed,
                      icon: const Icon(Icons.folder_open_outlined),
                      label: Text(buttonLabel),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
