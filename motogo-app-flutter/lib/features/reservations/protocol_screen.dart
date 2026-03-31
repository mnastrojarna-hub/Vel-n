import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../auth/widgets/toast_helper.dart';

/// Digital handover protocol — mirrors s-protocol from templates-done-pages.js.
/// Checklist: keys, insurance, gear, condition. PIN/biometric sign.
class ProtocolScreen extends StatefulWidget {
  const ProtocolScreen({super.key});

  @override
  State<ProtocolScreen> createState() => _ProtocolState();
}

class _ProtocolState extends State<ProtocolScreen> {
  bool _signed = false;
  final _pinCtrl = TextEditingController();
  bool _showPin = false;

  // Checklist items — mirrors the protocol template.
  // Locked items are always checked, unlocked can be toggled.
  final _items = <_CheckItem>[
    _CheckItem('🔑 Klíče od motorky', locked: true),
    _CheckItem('📄 Zelená karta (pojištění)', locked: true),
    _CheckItem('📋 Technický průkaz', locked: true),
    _CheckItem('🦺 Reflexní vesta', locked: true),
    _CheckItem('🩹 Lékárnička', locked: true),
    _CheckItem('🪖 Přilba řidiče'),
    _CheckItem('🧤 Rukavice'),
    _CheckItem('🧥 Bunda s chrániči'),
    _CheckItem('👖 Kalhoty s chrániči'),
  ];

  final _notesCtrl = TextEditingController();

  void _sign(String method) {
    if (method == 'biometric') {
      showMotoGoToast(context, icon: '🔐', title: 'Ověřuji', message: 'Biometrické ověření...');
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) _finalizeSig();
      });
    } else {
      setState(() => _showPin = true);
    }
  }

  void _confirmPin() {
    if (_pinCtrl.text.length < 4) {
      showMotoGoToast(context, icon: '⚠️', title: 'PIN', message: 'Zadejte alespoň 4místný PIN');
      return;
    }
    _finalizeSig();
  }

  void _finalizeSig() {
    setState(() { _signed = true; _showPin = false; });
    showMotoGoToast(context, icon: '✅', title: 'Podpis potvrzen', message: 'Protokol digitálně podepsán');
  }

  void _submit() {
    if (!_signed) {
      showMotoGoToast(context, icon: '⚠️', title: 'Podpis', message: 'Nejprve protokol digitálně podepište');
      return;
    }
    showMotoGoToast(context, icon: '📤', title: 'Odesláno', message: 'Předávací protokol odeslán MotoGo24');
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) context.pop();
    });
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      appBar: AppBar(title: const Text('📝 Předávací protokol'), backgroundColor: MotoGoColors.dark),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Checklist
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Výbava a vybavení', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                  const SizedBox(height: 10),
                  ..._items.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      GestureDetector(
                        onTap: item.locked ? null : () => setState(() => item.checked = !item.checked),
                        child: Container(
                          width: 22, height: 22,
                          decoration: BoxDecoration(
                            color: item.checked ? MotoGoColors.green : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: item.checked ? MotoGoColors.green : MotoGoColors.g200, width: 2),
                          ),
                          child: item.checked ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(item.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                          color: item.locked ? MotoGoColors.g400 : MotoGoColors.black)),
                      if (item.locked) const Text(' (povinné)', style: TextStyle(fontSize: 10, color: MotoGoColors.g400)),
                    ]),
                  )),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Notes
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Poznámky ke stavu', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                const SizedBox(height: 8),
                TextField(controller: _notesCtrl, maxLines: 3, decoration: const InputDecoration(hintText: 'Škrábance, poškození...')),
              ]),
            ),
            const SizedBox(height: 12),

            // Signature
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg)),
              child: Column(children: [
                const Text('Digitální podpis', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                const SizedBox(height: 10),
                if (!_signed && !_showPin) ...[
                  ElevatedButton.icon(
                    onPressed: () => _sign('biometric'),
                    icon: const Text('🔐', style: TextStyle(fontSize: 16)),
                    label: const Text('Podepsat biometrikou'),
                    style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => _sign('pin'),
                    child: const Text('Podepsat PINem'),
                  ),
                ],
                if (_showPin) ...[
                  TextField(controller: _pinCtrl, obscureText: true, keyboardType: TextInputType.number, maxLength: 6,
                    decoration: const InputDecoration(labelText: 'PIN (min. 4 číslice)'),
                    style: const TextStyle(letterSpacing: 4, fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  ElevatedButton(onPressed: _confirmPin, child: const Text('Potvrdit PIN')),
                ],
                if (_signed)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: MotoGoColors.greenPale, borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm)),
                    child: Row(children: [
                      const Text('✅', style: TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Podepsáno', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.greenDarker)),
                        Text(DateTime.now().toString().substring(0, 16), style: const TextStyle(fontSize: 10, color: MotoGoColors.g400)),
                      ])),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 16),

            // Submit
            ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: const Text('Odeslat protokol →'),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _CheckItem {
  final String label;
  final bool locked;
  bool checked;
  _CheckItem(this.label, {this.locked = false}) : checked = true;
}
