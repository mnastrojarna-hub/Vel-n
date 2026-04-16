import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import '../auth/widgets/toast_helper.dart';
import '../booking/booking_provider.dart';
import '../booking/booking_models.dart';
import 'shop_models.dart';
import 'shop_provider.dart';

/// Gift voucher screen — purchase + redeem.
/// Mirrors s-voucher from templates-shop.js + checkout redemption.
class VoucherScreen extends ConsumerStatefulWidget {
  const VoucherScreen({super.key});

  @override
  ConsumerState<VoucherScreen> createState() => _VoucherState();
}

class _VoucherState extends ConsumerState<VoucherScreen>
    with SingleTickerProviderStateMixin {
  // Purchase state
  int _amount = 1000;
  bool _printed = false;
  final _customCtrl = TextEditingController();
  bool _customMode = false;

  // Redeem state
  final _redeemCtrl = TextEditingController();
  bool _redeemLoading = false;
  String? _redeemMsg;
  bool? _redeemOk;
  final List<AppliedDiscount> _redeemedCodes = [];

  // Tab
  late TabController _tabCtrl;

  double get _total => _amount + (_printed ? printedVoucherShipping : 0);

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    _redeemCtrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  /// Validate and apply voucher code for redemption.
  Future<void> _redeemVoucher() async {
    final code = _redeemCtrl.text.trim();
    if (code.isEmpty) return;

    // Already applied?
    if (_redeemedCodes.any((d) => d.code == code.toUpperCase())) {
      setState(() {
        _redeemMsg = t(context).tr('promoAlreadyUsed').replaceAll('{code}', code.toUpperCase());
        _redeemOk = false;
      });
      return;
    }

    setState(() { _redeemLoading = true; _redeemMsg = null; });

    final result = await validateAndApplyCode(code);
    if (!mounted) return;
    setState(() => _redeemLoading = false);

    if (result.success && result.discount != null) {
      _redeemCtrl.clear();
      setState(() {
        _redeemedCodes.add(result.discount!);
        _redeemMsg = result.message(t(context).tr);
        _redeemOk = true;
      });
    } else {
      setState(() { _redeemMsg = result.message(t(context).tr); _redeemOk = false; });
    }
  }

  void _removeRedeemed(String code) {
    setState(() {
      _redeemedCodes.removeWhere((d) => d.code == code);
      _redeemMsg = null;
    });
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
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: MotoGoColors.green,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          tabs: [
            Tab(text: tr.tr('buyVoucherBtn')),
            Tab(text: tr.tr('redeemVoucher')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildPurchaseTab(tr),
          _buildRedeemTab(tr),
        ],
      ),
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

  /// Redeem tab — enter existing voucher code.
  Widget _buildRedeemTab(AppTranslations tr) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          // Instruction
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
              boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.1), blurRadius: 20)],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('🎁 ${tr.tr('redeemVoucher')}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
              const SizedBox(height: 8),
              Text(tr.tr('redeemVoucherDesc'),
                  style: const TextStyle(fontSize: 13, color: MotoGoColors.g400)),
              const SizedBox(height: 16),

              // Code input
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _redeemCtrl,
                    textCapitalization: TextCapitalization.characters,
                    onSubmitted: (_) => _redeemVoucher(),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: MotoGoColors.black, letterSpacing: 2),
                    decoration: InputDecoration(
                      hintText: tr.tr('enterCodeHint'),
                      hintStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: MotoGoColors.g400, letterSpacing: 0),
                      prefixIcon: const Icon(Icons.confirmation_number_outlined, color: MotoGoColors.g400),
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: MotoGoColors.g200, width: 2)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: MotoGoColors.green, width: 2)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _redeemLoading ? null : _redeemVoucher,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MotoGoColors.dark,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(90, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _redeemLoading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(tr.tr('apply').toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),

              // Result message
              if (_redeemMsg != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _redeemOk == true ? MotoGoColors.greenPale : MotoGoColors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      Text(_redeemOk == true ? '✓' : '✗',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                              color: _redeemOk == true ? MotoGoColors.greenDarker : MotoGoColors.red)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_redeemMsg!,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                              color: _redeemOk == true ? MotoGoColors.greenDarker : MotoGoColors.red))),
                    ]),
                  ),
                ),
            ]),
          ),

          // Applied vouchers list
          if (_redeemedCodes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(tr.tr('appliedVouchers').toUpperCase(),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: MotoGoColors.g400, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            for (final d in _redeemedCodes)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: MotoGoColors.greenPale,
                    borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
                    border: Border.all(color: MotoGoColors.green.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Text('🎁', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(d.code, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.greenDarker, letterSpacing: 1)),
                      Text('−${d.value.toStringAsFixed(0)} Kč',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MotoGoColors.greenDarker)),
                    ])),
                    GestureDetector(
                      onTap: () => _removeRedeemed(d.code),
                      child: const Text('✕', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: MotoGoColors.red)),
                    ),
                  ]),
                ),
              ),
          ],

          const SizedBox(height: 24),
          // How it works
          _buildRedeemInfoCard(tr),
        ],
      ),
    );
  }

  Widget _buildVoucherCard(AppTranslations tr) {
    return Container(
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
                  child: Text(tr.tr('giftVoucher').toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: 1)),
                ),
              ]),
              const SizedBox(height: 6),
              Text(tr.tr('giftVoucherTitle').toUpperCase(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 2)),
              const Divider(color: Colors.white24, height: 24),
              Text(tr.tr('voucherValueOf').toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: MotoGoColors.green, letterSpacing: 3)),
              const SizedBox(height: 8),
              Text('${_amount.toStringAsFixed(0)} Kč', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: MotoGoColors.green)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(50)),
                child: Text(
                  _printed ? '📦 ${tr.tr('printedVoucher')}' : '📧 ${tr.tr('electronicVoucher')}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.7)),
                ),
              ),
            ]),
          ),
        ],
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
        _infoRow('🏍️', tr.tr('voucherInfo4')),
        _infoRow('💚', tr.tr('voucherInfo5')),
      ]),
    );
  }

  Widget _buildRedeemInfoCard(AppTranslations tr) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
        boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.06), blurRadius: 16)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr.tr('howToRedeem'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
        const SizedBox(height: 8),
        _infoRow('1️⃣', tr.tr('redeemStep1')),
        _infoRow('2️⃣', tr.tr('redeemStep2')),
        _infoRow('3️⃣', tr.tr('redeemStep3')),
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
