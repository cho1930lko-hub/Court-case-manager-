import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/secure_backup_service.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _working = false;

  Future<String?> _askPassword({required String title}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller, obscureText: true, autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Backup password',
            helperText: 'कम से कम 12 अक्षर रखें। इसे सुरक्षित लिखकर रखें।',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('रद्द')),
          FilledButton(onPressed: () {
            if (controller.text.length < 12) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Password कम से कम 12 अक्षरों का होना चाहिए।')),
              );
              return;
            }
            Navigator.pop(context, controller.text);
          }, child: const Text('आगे बढ़ें')),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _createBackup() async {
    final password = await _askPassword(title: 'Encrypted Backup बनाएं');
    if (password == null) return;
    setState(() => _working = true);
    try {
      final bytes = await SecureBackupService.instance.createBackup(password);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Encrypted backup सेव करें',
        fileName: 'court_case_manager_backup.ccmbak',
        bytes: bytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(path == null ? 'Backup सेव करना रद्द किया गया।' : 'Encrypted backup सेव हो गया।'),
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Backup असफल: $e')));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _restoreBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Backup Restore करें?'),
        content: const Text('Restore करने पर इस मोबाइल का मौजूदा डेटाबेस और केस दस्तावेज़ चुने गए backup से बदल जाएंगे। पहले मौजूदा डेटा का अलग backup बना लें।'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('रद्द')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('मैं समझता/समझती हूँ, आगे बढ़ें')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['ccmbak'], withData: true,
    );
    if (picked == null || picked.files.single.bytes == null) return;
    final password = await _askPassword(title: 'Backup password डालें');
    if (password == null) return;
    setState(() => _working = true);
    try {
      await SecureBackupService.instance.restoreBackup(picked.files.single.bytes!, password);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Restore पूरा हुआ। कृपया ऐप बंद करके दोबारा खोलें।'),
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Restore असफल: $e')));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Backup & Restore')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: const [
          Icon(Icons.lock, size: 34, color: Color(0xFF3158B7)),
          SizedBox(height: 10),
          Text('AES-256-GCM Encrypted Backup', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          SizedBox(height: 6),
          Text('Database और ऐप के Case Documents को password से encrypted backup में रखा जाता है।'),
          SizedBox(height: 8),
          Text('Password भूलने पर backup वापस नहीं खोला जा सकेगा। इसे सुरक्षित रखें।', style: TextStyle(color: Colors.redAccent)),
        ],
      ))),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _working ? null : _createBackup,
        icon: const Icon(Icons.backup), label: const Text('नया Encrypted Backup बनाएं'),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: _working ? null : _restoreBackup,
        icon: const Icon(Icons.restore), label: const Text('Backup से Restore करें'),
      ),
      if (_working) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      const SizedBox(height: 18),
      const Text('महत्वपूर्ण: मौजूदा SQLite database अभी device पर encrypted नहीं है। यह सुविधा backup file को encrypt करती है, live database को नहीं। Database-at-rest encryption और App Lock अगले सुरक्षा उपचरण में लागू व जाँचे जाएंगे। वास्तविक संवेदनशील रिकॉर्ड अभी न डालें।',
        style: TextStyle(color: Colors.redAccent, height: 1.4)),
    ]),
  );
}
