import 'package:flutter/material.dart';
import '../services/app_lock_service.dart';

/// Mandatory local PIN gate. The child tree is not built until a PIN has
/// been configured and the current app session has been unlocked.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate>
    with WidgetsBindingObserver {
  final _lock = AppLockService.instance;
  bool _loading = true;
  bool _configured = false;
  bool _unlocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadConfiguration();
  }

  Future<void> _loadConfiguration() async {
    try {
      final configured = await _lock.isConfigured;
      if (!mounted) return;
      setState(() {
        _configured = configured;
        _unlocked = false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Lock as soon as the app leaves the foreground. Do not rely on a timer:
    // a paused app must never resume into the previously visible case screen.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_unlocked && mounted) {
        setState(() => _unlocked = false);
      }
    }
  }

  Future<void> _onPinConfigured() async {
    if (!mounted) return;
    setState(() {
      _configured = true;
      _unlocked = true;
    });
  }

  Future<void> _onUnlocked() async {
    if (!mounted) return;
    setState(() => _unlocked = true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_configured || !_unlocked) {
      return _PinEntryScreen(
        key: ValueKey(_configured ? 'unlock' : 'setup'),
        isSetup: !_configured,
        onPinConfigured: _onPinConfigured,
        onUnlocked: _onUnlocked,
      );
    }
    return widget.child;
  }
}

class _PinEntryScreen extends StatefulWidget {
  const _PinEntryScreen({
    super.key,
    required this.isSetup,
    required this.onPinConfigured,
    required this.onUnlocked,
  });

  final bool isSetup;
  final Future<void> Function() onPinConfigured;
  final Future<void> Function() onUnlocked;

  @override
  State<_PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends State<_PinEntryScreen> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final pin = _pin.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.isSetup) {
        if (!AppLockService.isValidPinFormat(pin)) {
          throw ArgumentError('PIN 6 से 8 अंकों का होना चाहिए।');
        }
        if (_confirm.text.trim() != pin) {
          throw StateError('दोनों PIN एक जैसे नहीं हैं।');
        }
        await AppLockService.instance.setPin(pin);
        await widget.onPinConfigured();
      } else {
        final valid = await AppLockService.instance.verifyPin(pin);
        if (!valid) {
          throw StateError('PIN गलत है। कृपया दोबारा प्रयास करें।');
        }
        await widget.onUnlocked();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Bad state: ', '').replaceFirst('Invalid argument(s): ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final setup = widget.isSetup;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F6FA),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                    side: const BorderSide(color: Color(0xFFE3E9F1)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF3F1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(Icons.lock_rounded,
                              size: 30, color: Color(0xFF18766D)),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          setup ? 'ऐप सुरक्षा सेटअप' : 'ऐप अनलॉक करें',
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF172B4D),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          setup
                              ? 'पहली बार उपयोग से पहले 6 से 8 अंकों का PIN बनाएँ। इसे सुरक्षित रखें।'
                              : 'आपके केस और रजिस्टर सुरक्षित हैं। आगे बढ़ने के लिए अपना PIN डालें।',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Color(0xFF68778D), height: 1.5),
                        ),
                        const SizedBox(height: 22),
                        _pinField(_pin, setup ? 'नया PIN' : 'PIN दर्ज करें'),
                        if (setup) ...[
                          const SizedBox(height: 12),
                          _pinField(_confirm, 'PIN दोबारा दर्ज करें'),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(11),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF0EE),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                  color: Color(0xFFAD4037), fontSize: 12),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: FilledButton(
                            onPressed: _busy ? null : _submit,
                            child: _busy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : Text(setup ? 'PIN सुरक्षित करें' : 'अनलॉक करें'),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.shield_outlined,
                                size: 15, color: Color(0xFF18766D)),
                            SizedBox(width: 6),
                            Text(
                              'PIN इस डिवाइस के Secure Storage में सुरक्षित है',
                              style: TextStyle(
                                  color: Color(0xFF68778D), fontSize: 10),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pinField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      obscureText: _obscure,
      maxLength: 8,
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        prefixIcon: const Icon(Icons.password_rounded),
        suffixIcon: IconButton(
          tooltip: _obscure ? 'PIN दिखाएँ' : 'PIN छिपाएँ',
          onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
