import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import '../auth/widgets/toast_helper.dart';
import 'shop_models.dart';
import 'shop_provider.dart';

/// Gift voucher screen — purchase only.
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
    final tr = t(context);
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
        title: Text('🎁 ${tr.tr('giftVoucher')}'),
        backgroundColor: MotoGoColors.dark,
      ),
      body: _buildPurchaseTab(tr),
    );
  }

  /// Purchase tab — buy new voucher.
  Widget _buildPurchaseTab(AppTranslations tr) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Voucher card visual
          _buildVoucherCard(tr),
          const SizedBox(height: 20),

          // Amount selection
          Text(tr.tr('voucherValue'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
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
                  child: Text('$amt Kč', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: active ? Colors.black : MotoGoColors.black)),
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
                  child: Text(tr.tr('other'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _customMode ? Colors.black : MotoGoColors.black)),
                ),
              ),
            ),
          ),
          if (_customMode) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _customCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: tr.tr('amountMin'), suffixText: 'Kč'),
              onChanged: (v) {
                final parsed = int.tryParse(v) ?? 100;
                setState(() => _amount = parsed.clamp(100, 99999));
              },
            ),
          ],
          const SizedBox(height: 20),

          // Type toggle
          Text(tr.tr('voucherTypeLabel'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
          const SizedBox(height: 8),
          Row(
            children: [
              _TypeBtn(label: '📧 ${tr.tr('electronicVoucher')}', sublabel: 'Email · ${tr.free.toLowerCase()}', active: !_printed,
                onTap: () => setState(() => _printed = false)),
              const SizedBox(width: 8),
              _TypeBtn(label: '📦 ${tr.tr('printedVoucher')}', sublabel: '+ ${printedVoucherShipping.toStringAsFixed(0)} Kč', active: _printed,
                onTap: () => setState(() => _printed = true)),
            ],
          ),
          const SizedBox(height: 24),

          // Buy button
          ElevatedButton(
            onPressed: _amount < 100 ? null : () {
              ref.read(cartProvider.notifier).addItem(
                'voucher_${_amount.toInt()}_${_printed ? "p" : "d"}_${DateTime.now().millisecondsSinceEpoch}',
                '${tr.tr('giftVoucher')} ${_amount.toStringAsFixed(0)} Kč${_printed ? " (${tr.tr('printedVoucher').toLowerCase()})" : ""}',
                _total,
              );
              showMotoGoToast(context, icon: '✓', title: tr.tr('addedToCart'), message: '${_total.toStringAsFixed(0)} Kč');
              context.push(Routes.cart);
            },
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.card_giftcard, size: 18),
              const SizedBox(width: 8),
              Text('${tr.tr('buyVoucherBtn')} · ${_total.toStringAsFixed(0)} Kč →'),
            ]),
          ),

          const SizedBox(height: 20),
          // Info card
          _buildInfoCard(tr),
        ],
      ),
    );
  }

  Widget _buildVoucherCard(AppTranslations tr) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
      child: Container(
        decoration: BoxDecoration(
          boxShadow: [BoxShadow(color: MotoGoColors.dark.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Image.asset(
          'assets/darkovy-poukaz.jpg',
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildInfoCard(AppTranslations tr) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
        boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.06), blurRadius: 16)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr.tr('howItWorks'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
        const SizedBox(height: 8),
        _infoRow('✅', tr.tr('voucherInfo1')),
        _infoRow('🗓️', tr.tr('voucherInfo2')),
        _infoRow('📧', tr.tr('voucherInfo3')),
        _infoRow('💚', tr.tr('voucherInfo5')),
      ]),
    );
  }

  Widget _infoRow(String icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(icon, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: MotoGoColors.g400))),
      ]),
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
