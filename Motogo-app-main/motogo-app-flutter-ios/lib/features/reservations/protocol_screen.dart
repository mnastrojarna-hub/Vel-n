import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
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
  late final List<_CheckItem> _items;

  List<_CheckItem> _buildItems() => [
    _CheckItem('🔑 ${t(context).tr('protoKeys')}', locked: true),
    _CheckItem('📄 ${t(context).tr('protoInsurance')}', locked: true),
    _CheckItem('📋 ${t(context).tr('protoTechDoc')}', locked: true),
    _CheckItem('🦺 ${t(context).tr('protoVest')}', locked: true),
    _CheckItem('🩹 ${t(context).tr('protoFirstAid')}', locked: true),
    _CheckItem('🪖 ${t(context).tr('protoHelmet')}'),
    _CheckItem('🧤 ${t(context).tr('protoGloves')}'),
    _CheckItem('🧥 ${t(context).tr('protoJacket')}'),
    _CheckItem('👖 ${t(context).tr('protoPants')}'),
  ];
  bool _itemsBuilt = false;

  final _notesCtrl = TextEditingController();

  void _sign(String method) {
    if (method == 'biometric') {
      showMotoGoToast(context, icon: '🔐', title: t(context).tr('verifying'), message: t(context).tr('biometricVerification'));
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) _finalizeSig();
      });
    } else {
      setState(() => _showPin = true);
    }
  }

  void _confirmPin() {
    if (_pinCtrl.text.length < 4) {
      showMotoGoToast(context, icon: '⚠️', title: 'PIN', message: t(context).tr('pinMinLength'));
      return;
    }
    _finalizeSig();
  }

  void _finalizeSig() {
    setState(() { _signed = true; _showPin = false; });
    showMotoGoToast(context, icon: '✅', title: t(context).tr('signatureConfirmed'), message: t(context).tr('protocolSigned'));
  }

  void _submit() {
    if (!_signed) {
      showMotoGoToast(context, icon: '⚠️', title: t(context).tr('signatureLabel'), message: t(context).tr('signFirst'));
      return;
    }
    showMotoGoToast(context, icon: '📤', title: t(context).tr('sent'), message: t(context).tr('protocolSent'));
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
    if (!_itemsBuilt) { _items = _buildItems(); _itemsBuilt = true; }
    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      appBar: AppBar(
        leading: GestureDetector(
          onTap: () => context.pop(),
          child: Center(
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(10)),
              child: const Center(child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black))),
            ),
          ),
        ),
        title: Text('📝 ${t(context).tr('protocolTitle')}'), backgroundColor: MotoGoColors.dark),
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
                  Text(t(context).tr('gearAndEquipment'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
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
                          child: item.checked ? const Icon(Icons.check, size: 14, color: Colors.black) : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(item.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                          color: item.locked ? MotoGoColors.g400 : MotoGoColors.black)),
                      if (item.locked) Text(' (${t(context).tr('mandatory')})', style: const TextStyle(fontSize: 10, color: MotoGoColors.g400)),
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
                Text(t(context).tr('conditionNotes'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                const SizedBox(height: 8),
                TextField(controller: _notesCtrl, maxLines: 3, decoration: InputDecoration(hintText: t(context).tr('scratchesDamage'))),
              ]),
            ),
            const SizedBox(height: 12),

            // Signature
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg)),
              child: Column(children: [
                Text(t(context).tr('digitalSignature'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                const SizedBox(height: 10),
                if (!_signed && !_showPin) ...[
                  ElevatedButton.icon(
                    onPressed: () => _sign('biometric'),
                    icon: const Text('🔐', style: TextStyle(fontSize: 16)),
                    label: Text(t(context).tr('signBiometric')),
                    style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _sign('pin'),
                    icon: const Icon(Icons.pin, size: 16),
                    label: Text(t(context).tr('signPin')),
                  ),
                ],
                if (_showPin) ...[
                  TextField(controller: _pinCtrl, obscureText: true, keyboardType: TextInputType.number, maxLength: 6,
                    decoration: InputDecoration(labelText: t(context).tr('pinLabel')),
                    style: const TextStyle(letterSpacing: 4, fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(onPressed: _confirmPin, icon: const Icon(Icons.check, size: 16), label: Text(t(context).tr('confirmPin'))),
                ],
                if (_signed)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: MotoGoColors.greenPale, borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm)),
                    child: Row(children: [
                      const Text('✅', style: TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t(context).tr('signed'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.greenDarker)),
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
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.send, size: 18),
                const SizedBox(width: 8),
                Text(t(context).tr('sendProtocol')),
              ]),
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
