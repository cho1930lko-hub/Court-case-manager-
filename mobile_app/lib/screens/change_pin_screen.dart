import 'package:flutter/material.dart';
import '../services/app_lock_service.dart';
import '../theme/app_theme.dart';

class ChangePinScreen extends StatefulWidget {
  const ChangePinScreen({super.key});

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  final _formKey = GlobalKey<FormState>();
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _showOld = false;
  bool _showNew = false;
  bool _showConfirm = false;

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _validatePin(String? value) {
    final pin = value ?? '';
    if (!RegExp(r'^\\d{6,8}$').hasMatch(pin)) {
      return 'PIN में 6 से 8 अंक होने चाहिए।';
    }
    return null;
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (_new.text != _confirm.text) {
      setState(() {});
      return;
    }
    setState(() => _busy = true);
    try {
      await AppLockService.instance.changePin(
        oldPin: _old.text,
        newPin: _new.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('App PIN सफलतापूर्वक बदल दिया गया।')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Bad state: ', '').replaceFirst('Invalid argument(s): ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PIN नहीं बदला: $message')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _pinField({
    required TextEditingController controller,
    required String label,
    required bool visible,
    required ValueChanged<bool> onVisibilityChanged,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: !visible,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      maxLength: 8,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: _validatePin,
      decoration: InputDecoration(
        labelText: label,
        hintText: '6–8 अंक',
        counterText: '',
        prefixIcon: const Icon(Icons.password_rounded),
        suffixIcon: IconButton(
          tooltip: visible ? 'PIN छिपाएँ' : 'PIN दिखाएँ',
          onPressed: () => onVisibilityChanged(!visible),
          icon: Icon(visible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mismatch = _confirm.text.isNotEmpty && _new.text != _confirm.text;
    return Scaffold(
      appBar: AppBar(title: const Text('App PIN बदलें')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF0F7),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.line),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.shield_outlined, color: AppTheme.blue, size: 27),
                    SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('अपनी ऐप सुरक्षा बनाए रखें',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.ink)),
                          SizedBox(height: 5),
                          Text('PIN बदलने के लिए वर्तमान PIN आवश्यक है। नया PIN 6 से 8 अंकों का रखें।',
                            style: TextStyle(fontSize: 12, height: 1.45, color: AppTheme.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text('PIN विवरण',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.ink)),
              const SizedBox(height: 13),
              _pinField(
                controller: _old,
                label: 'वर्तमान PIN',
                visible: _showOld,
                onVisibilityChanged: (v) => setState(() => _showOld = v),
              ),
              const SizedBox(height: 14),
              _pinField(
                controller: _new,
                label: 'नया PIN',
                visible: _showNew,
                onVisibilityChanged: (v) => setState(() => _showNew = v),
              ),
              const SizedBox(height: 14),
              _pinField(
                controller: _confirm,
                label: 'नया PIN दोबारा डालें',
                visible: _showConfirm,
                onVisibilityChanged: (v) => setState(() => _showConfirm = v),
                validator: (value) {
                  final error = _validatePin(value);
                  if (error != null) return error;
                  if (value != _new.text) return 'दोनों नए PIN एक जैसे नहीं हैं।';
                  return null;
                },
              ),
              if (mismatch)
                const Padding(
                  padding: EdgeInsets.only(top: 4, left: 4),
                  child: Text('नया PIN और पुष्टि एक जैसे नहीं हैं।',
                    style: TextStyle(color: Color(0xFFB5473C), fontSize: 12)),
                ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7E9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFF0E2C8)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, color: Color(0xFF9A6A27), size: 19),
                    SizedBox(width: 9),
                    Expanded(
                      child: Text('PIN भूलने पर ऐप में bypass उपलब्ध नहीं है। अपने encrypted backup और उसकी password जानकारी को सुरक्षित रखें।',
                        style: TextStyle(fontSize: 12, height: 1.45, color: Color(0xFF76572D))),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.lock_reset_rounded),
                  label: Text(_busy ? 'PIN बदला जा रहा है…' : 'नया PIN सुरक्षित करें'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
