import 'package:flutter/material.dart';
import '../services/app_lock_service.dart';

class ChangePinScreen extends StatefulWidget {
  const ChangePinScreen({super.key});
  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() { _old.dispose(); _new.dispose(); _confirm.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_new.text != _confirm.text) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('नया PIN और पुष्टि एक जैसे नहीं हैं।')));
      return;
    }
    setState(() => _busy = true);
    try {
      await AppLockService.instance.changePin(oldPin: _old.text, newPin: _new.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('App PIN सफलतापूर्वक बदल गया।')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PIN नहीं बदला: $e')));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('App PIN बदलें')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('PIN बदलने के लिए वर्तमान PIN आवश्यक है। PIN भूल जाने पर ऐप में कोई bypass उपलब्ध नहीं है; अपने सुरक्षित backup और उसकी password जानकारी को सुरक्षित रखें।', style: TextStyle(height: 1.4)),
      const SizedBox(height: 18),
      TextField(controller: _old, obscureText: true, keyboardType: TextInputType.number, maxLength: 8,
        decoration: const InputDecoration(labelText: 'वर्तमान PIN', border: OutlineInputBorder())),
      const SizedBox(height: 10),
      TextField(controller: _new, obscureText: true, keyboardType: TextInputType.number, maxLength: 8,
        decoration: const InputDecoration(labelText: 'नया PIN (6–8 अंक)', border: OutlineInputBorder())),
      const SizedBox(height: 10),
      TextField(controller: _confirm, obscureText: true, keyboardType: TextInputType.number, maxLength: 8,
        decoration: const InputDecoration(labelText: 'नया PIN दोबारा डालें', border: OutlineInputBorder())),
      const SizedBox(height: 16),
      FilledButton(onPressed: _busy ? null : _save, child: _busy ? const CircularProgressIndicator() : const Text('PIN बदलें')),
    ]),
  );
}
