import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../auth/widgets/toast_helper.dart';
import 'shop_models.dart';
import 'shop_provider.dart';

/// Gift voucher purchase — mirrors s-voucher from templates-shop.js.
/// Amount selection, digital/printed toggle, add to cart.
class VoucherScreen extends ConsumerStatefulWidget {
  const VoucherScreen({super.key});

  @override
  ConsumerState<VoucherScreen> createState() => _VoucherState();
}

class _VoucherState extends ConsumerState<VoucherScreen> {
  int _amount = 1000;
  bool _printed = false;
  final _customCtrl = TextEditingController();
  bool _customMode = false;

  double get _total => _amount + (_printed ? printedVoucherShipping : 0);

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      appBar: AppBar(title: const Text('🎁 Dárkový poukaz'), backgroundColor: MotoGoColors.dark),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Voucher card visual
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [MotoGoColors.dark, Color(0xFF2D4A35)]),
                borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
              ),
              child: Column(children: [
                const Text('🏍️ MOTO GO 24', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                const Text('DÁRKOVÝ POUKAZ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: MotoGoColors.green, letterSpacing: 3)),
                const SizedBox(height: 16),
                Text('${_amount.toStringAsFixed(0)} Kč', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: MotoGoColors.green)),
                const SizedBox(height: 4),
                Text(_printed ? 'Tištěný + poštovné' : 'Elektronický', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6))),
              ]),
            ),
            const SizedBox(height: 20),

            // Amount selection
            const Text('Hodnota poukazu', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: [500, 1000, 2000].map((amt) {
                final active = _amount == amt && !_customMode;
                return GestureDetector(
                  onTap: () => setState(() { _amount = amt; _customMode = false; }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: active ? MotoGoColors.green : Colors.white,
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(color: active ? MotoGoColors.green : MotoGoColors.g200, width: 2),
                    ),
                    child: Text('$amt Kč', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: active ? Colors.white : MotoGoColors.black)),
                  ),
                );
              }).toList()..add(
                GestureDetector(
                  onTap: () => setState(() => _customMode = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: _customMode ? MotoGoColors.green : Colors.white,
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(color: _customMode ? MotoGoColors.green : MotoGoColors.g200, width: 2),
                    ),
                    child: Text('Jiná', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _customMode ? Colors.white : MotoGoColors.black)),
                  ),
                ),
              ),
            ),
            if (_customMode) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _customCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Částka (min. 100 Kč)', suffixText: 'Kč'),
                onChanged: (v) {
                  final parsed = int.tryParse(v) ?? 100;
                  setState(() => _amount = parsed.clamp(100, 99999));
                },
              ),
            ],
            const SizedBox(height: 20),

            // Type toggle
            const Text('Typ poukazu', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
            const SizedBox(height: 8),
            Row(
              children: [
                _TypeBtn(label: '📧 Elektronický', sublabel: 'Email · zdarma', active: !_printed,
                  onTap: () => setState(() => _printed = false)),
                const SizedBox(width: 8),
                _TypeBtn(label: '📦 Tištěný', sublabel: '+ ${printedVoucherShipping.toStringAsFixed(0)} Kč poštovné', active: _printed,
                  onTap: () => setState(() => _printed = true)),
              ],
            ),
            const SizedBox(height: 24),

            // Buy button
            ElevatedButton(
              onPressed: _amount < 100 ? null : () {
                ref.read(cartProvider.notifier).addItem(
                  'voucher',
                  'Dárkový poukaz ${_amount.toStringAsFixed(0)} Kč${_printed ? " (tištěný)" : ""}',
                  _total,
                );
                showMotoGoToast(context, icon: '✓', title: 'Přidáno do košíku', message: '${_total.toStringAsFixed(0)} Kč');
                context.push(Routes.cart);
              },
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: Text('Koupit poukaz · ${_total.toStringAsFixed(0)} Kč →'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeBtn extends StatelessWidget {
  final String label; final String sublabel; final bool active; final VoidCallback onTap;
  const _TypeBtn({required this.label, required this.sublabel, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: active ? MotoGoColors.greenPale : Colors.white,
          borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
          border: Border.all(color: active ? MotoGoColors.green : MotoGoColors.g200, width: active ? 2 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: active ? MotoGoColors.greenDarker : MotoGoColors.black)),
          Text(sublabel, style: const TextStyle(fontSize: 10, color: MotoGoColors.g400)),
        ]),
      ),
    ),
  );
}
