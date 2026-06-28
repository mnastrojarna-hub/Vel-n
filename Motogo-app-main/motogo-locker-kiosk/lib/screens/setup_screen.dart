import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api.dart';
import '../services/kiosk_storage.dart';

/// Jednorázové spárování tabletu s pobočkou (kód pobočky + kiosk token z Velína).
class SetupScreen extends StatefulWidget {
  final VoidCallback onDone;
  const SetupScreen({super.key, required this.onDone});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _branch = TextEditingController(text: KioskStorage.instance.branchCode ?? '');
  final _token = TextEditingController(text: KioskStorage.instance.token ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _branch.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await KioskApi.instance.validatePairing(_branch.text, _token.text);
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    await KioskStorage.instance.save(branchCode: _branch.text, token: _token.text);
    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: MG.bgGradient),
        alignment: Alignment.center,
        child: SingleChildScrollView(
          child: Container(
            width: 520,
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(36),
            decoration: MG.glass(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset('assets/logo.png', height: 64),
                const SizedBox(height: 24),
                const Text('Nastavení kiosku',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: MG.white, fontSize: 26, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text('Spárujte tablet s pobočkou. Údaje najdete ve Velíně → Pobočky → Samoobsluha.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: MG.white.withValues(alpha: 0.7), fontSize: 15)),
                const SizedBox(height: 28),
                _field('Kód pobočky', _branch, 'např. 000126'),
                const SizedBox(height: 16),
                _field('Kiosk token', _token, 'UUID z Velína'),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: MG.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: MG.red),
                    ),
                    child: Text(_error!, style: const TextStyle(color: MG.white, fontSize: 15)),
                  ),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  height: 60,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: MG.green,
                      foregroundColor: MG.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _busy ? null : _save,
                    child: _busy
                        ? const SizedBox(
                            width: 26, height: 26,
                            child: CircularProgressIndicator(strokeWidth: 3, color: MG.black))
                        : const Text('Spárovat a spustit',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController c, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: MG.white.withValues(alpha: 0.8), fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          style: const TextStyle(color: MG.white, fontSize: 18),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: MG.white.withValues(alpha: 0.35)),
            filled: true,
            fillColor: MG.white.withValues(alpha: 0.06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: MG.white.withValues(alpha: 0.15)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: MG.white.withValues(alpha: 0.15)),
            ),
          ),
        ),
      ],
    );
  }
}
