import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_space.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../booking_models.dart';
import '../../my_vouchers.dart' show MyVoucher;
import '../booking_v2_parts.dart';

/// v2 look of `BookingFormPromoSection` (V branch): "Zadat kód" opens the
/// section's EXISTING code dialog (validation, `min_order_amount`, no two
/// percent codes — all inside it); applied codes as ✓ rows with the SAME
/// remove closure.
class BookingPromoV2 extends StatelessWidget {
  final List<AppliedDiscount> discounts;
  final VoidCallback onOpen;
  final void Function(AppliedDiscount) onRemove;

  /// Vlastní neuplatněné dárkové poukazy — klepnutí = [onVoucher] (dialog
  /// kód rovnou uplatní stejnou cestou jako napsaný; 2026-10-22).
  final List<MyVoucher> vouchers;
  final ValueChanged<String>? onVoucher;

  const BookingPromoV2({
    super.key,
    required this.discounts,
    required this.onOpen,
    required this.onRemove,
    this.vouchers = const [],
    this.onVoucher,
  });

  /// Same text as the old applied-code row.
  static String label(AppliedDiscount d) => d.type == DiscountType.percent
      ? '${d.code} (−${d.value.toStringAsFixed(0)}%)'
      : '${d.code} (−${bkMoney(d.calculatedAmount > 0 ? d.calculatedAmount : d.value)})';

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return BkCard(
      icon: MgIcons.tag,
      title: tr.tr('v2BkPromoTitle'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          button: true,
          label: tr.tr('v2BkPromoAdd'),
          excludeSemantics: true,
          onTap: onOpen,
          child: MgPress(
            onTap: onOpen,
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: MgColors.surface,
                borderRadius: BorderRadius.circular(MgRadius.button),
                border: Border.all(color: MgColors.lineInput, width: 1.5),
              ),
              child: Row(children: [
                MgIcon(MgIcons.plus, size: 20, color: MgColors.link),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(tr.tr('v2BkPromoAdd'),
                      style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.link)),
                ),
                MgIcon(MgIcons.chevronRight, size: 18, color: MgColors.link),
              ]),
            ),
          ),
        ),
        if (vouchers.isNotEmpty && onVoucher != null) _vouchers(tr),
        for (final d in discounts)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: MgEnter(
              child: Container(
                padding: const EdgeInsets.only(left: 12),
                decoration: BoxDecoration(
                  color: MgColors.tintOk,
                  borderRadius: BorderRadius.circular(MgRadius.action),
                  border: Border.all(color: MgColors.tintOkBorder),
                ),
                child: Row(children: [
                  MgIcon(MgIcons.checkCircle, size: 18, color: MgColors.link),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(label(d),
                        style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onTintOk))),
                  ),
                  Semantics(
                    button: true,
                    label: tr.trArgs('v2BkPromoRemove', {'code': d.code}),
                    excludeSemantics: true,
                    onTap: () => onRemove(d),
                    child: MgPress(
                      onTap: () => onRemove(d),
                      child: SizedBox(
                        width: 48,
                        height: 44,
                        child: Center(child: MgIcon(MgIcons.close, size: 18, color: MgColors.onTintOk)),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _vouchers(AppTranslations tr) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr.tr('bkMyVouchers'), style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.lead)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final v in vouchers)
              Semantics(
                button: true,
                label: tr.trArgs('bkVoucherUseA11y', {'code': v.code, 'amount': bkMoney(v.amount)}),
                excludeSemantics: true,
                onTap: () => onVoucher!(v.code),
                child: MgPress(
                  onTap: () => onVoucher!(v.code),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: MgColors.tintOk,
                      borderRadius: BorderRadius.circular(MgRadius.action),
                      border: Border.all(color: MgColors.tintOkBorder),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      MgIcon(MgIcons.tag, size: 16, color: MgColors.link),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text('${v.code} · ${bkNb(bkMoney(v.amount))}',
                            style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onTintOk))),
                      ),
                    ]),
                  ),
                ),
              ),
          ]),
        ]),
      );
}
