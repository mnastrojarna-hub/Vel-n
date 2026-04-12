import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
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
      appBar: AppBar(title: Text('🎁 ${t(context).tr('giftVoucher')}'), backgroundColor: MotoGoColors.dark),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Voucher card visual — prominent design
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [MotoGoColors.dark, Color(0xFF2D4A35)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
                boxShadow: [BoxShadow(color: MotoGoColors.dark.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: Stack(
                children: [
                  Positioned(right: 16, bottom: 16, child: Icon(Icons.motorcycle, size: 80, color: MotoGoColors.green.withValues(alpha: 0.08))),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('🏍️ MOTO GO 24', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(4)),
                          child: Text(t(context).tr('giftVoucher').toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1)),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Text(t(context).tr('giftVoucherTitle').toUpperCase(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 2)),
                      const Divider(color: Colors.white24, height: 24),
                      const Text('V HODNOTĚ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: MotoGoColors.green, letterSpacing: 3)),
                      const SizedBox(height: 8),
                      Text('${_amount.toStringAsFixed(0)} Kč', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: MotoGoColors.green)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(50)),
                        child: Text(
                          _printed ? '📦 ${t(context).tr('printedVoucher')}' : '📧 ${t(context).tr('electronicVoucher')}',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.7)),
                        ),
                      ),
                    ]),
                  ),
                ],
              ),
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
                    child: Text(t(context).tr('other'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _customMode ? Colors.white : MotoGoColors.black)),
                  ),
                ),
              ),
            ),
            if (_customMode) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _customCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: t(context).tr('amountMin'), suffixText: 'Kč'),
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
                _TypeBtn(label: '📧 ${t(context).tr('electronicVoucher')}', sublabel: 'Email · ${t(context).tr('free').toLowerCase()}', active: !_printed,
                  onTap: () => setState(() => _printed = false)),
                const SizedBox(width: 8),
                _TypeBtn(label: '📦 ${t(context).tr('printedVoucher')}', sublabel: '+ ${printedVoucherShipping.toStringAsFixed(0)} Kč', active: _printed,
                  onTap: () => setState(() => _printed = true)),
              ],
            ),
            const SizedBox(height: 24),

            // Buy button
            ElevatedButton(
              onPressed: _amount < 100 ? null : () {
                ref.read(cartProvider.notifier).addItem(
                  'voucher_${_amount.toInt()}_${_printed ? "p" : "d"}_${DateTime.now().millisecondsSinceEpoch}',
                  '${t(context).tr('giftVoucher')} ${_amount.toStringAsFixed(0)} Kč${_printed ? " (${t(context).tr('printedVoucher').toLowerCase()})" : ""}',
                  _total,
                );
                showMotoGoToast(context, icon: '✓', title: t(context).tr('addedToCart'), message: '${_total.toStringAsFixed(0)} Kč');
                context.push(Routes.cart);
              },
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.card_giftcard, size: 18),
                const SizedBox(width: 8),
                Text('${t(context).tr('buyVoucherBtn')} · ${_total.toStringAsFixed(0)} Kč →'),
              ]),
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
