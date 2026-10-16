import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/v2/widgets/mg_chips.dart';
import '../../../../core/v2/widgets/mg_price.dart';
import '../../../loyalty/loyalty_provider.dart';
import '../../../loyalty/rank_names.dart';
import '../../booking_models.dart';
import '../booking_v2_parts.dart';

/// v2 look of `BookingFormPriceSection` (V branch): the white receipt with
/// EXACTLY the old rows and conditions (bike × days, extras at rank price,
/// delivery / return fee, discount, loyalty, late pickup, no deposit) and
/// the dark total box (`totalFinal`, the same `bd.total`, VAT note, rank
/// savings chip). A failed loyalty load is said out loud with a retry.
class BookingPriceV2 extends ConsumerWidget {
  final BookingDraft draft;
  final PriceBreakdown bd;
  final int dayCount;
  final List<SelectedExtra>? pricedExtras;

  const BookingPriceV2({
    super.key,
    required this.draft,
    required this.bd,
    required this.dayCount,
    this.pricedExtras,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final loyalty = ref.watch(loyaltyStatusProvider);
    Widget row(String label, String value, {bool ok = false, bool subtle = false, String? icon}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (icon != null) ...[
              Padding(padding: const EdgeInsets.only(top: 1), child: MgIcon(icon, size: 16, color: MgColors.link)),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(label,
                  style: MgType.small.copyWith(
                      fontWeight: subtle ? FontWeight.w600 : FontWeight.w700, color: subtle ? MgColors.meta : MgColors.body2)),
            ),
            const SizedBox(width: 10),
            Text(value,
                style: MgType.tab(MgType.small.copyWith(
                    fontWeight: FontWeight.w800, color: ok ? MgColors.link : (subtle ? MgColors.meta : MgColors.ink)))),
          ]),
        );
    final dc = dayCount;
    return BkCard(
      icon: MgIcons.receipt,
      title: tr.priceSummary,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        row('${tr.motorcycle} × ${bkDays(tr, dc)}', bkMoney(bd.basePrice)),
        for (final e in (pricedExtras ?? draft.extras))
          row(extraLabel(tr.tr, e.id, e.name),
              e.price == 0 ? tr.tr('gearFree') : '+${bkMoney(e.price * e.quantity)}', ok: e.price == 0),
        if (bd.pickupDeliveryFee > 0) row(tr.tr('deliveryFee'), '+${bkMoney(bd.pickupDeliveryFee)}'),
        if (bd.returnDeliveryFee > 0) row(tr.tr('returnFee'), '+${bkMoney(bd.returnDeliveryFee)}'),
        if (bd.discountTotal > 0) row(tr.tr('discountLabel'), '−${bkMoney(bd.discountTotal)}', ok: true),
        if (bd.loyaltyDiscount > 0)
          row(
            tr
                .tr('loyaltyDiscountLabel')
                .replaceAll('{rank}', localizedRankName(tr, bd.loyaltyLevel, bd.loyaltyRankName ?? ''))
                .replaceAll('{pct}', '${bd.loyaltyPercent}'),
            '−${bkMoney(bd.loyaltyDiscount)}',
            ok: true,
          ),
        if (bd.latePickupDiscount > 0) row(tr.tr('latePickupDiscountLabel'), '−${bkMoney(bd.latePickupDiscount)}', ok: true),
        row(tr.tr('depositNotCharged'), bkMoney(0), subtle: true, icon: MgIcons.checkCircle),
        if (loyalty.hasError && !loyalty.isLoading) ...[
          const SizedBox(height: 6),
          Row(children: [
            MgIcon(MgIcons.info, size: 16, color: MgColors.warn),
            const SizedBox(width: 6),
            Expanded(child: Text(tr.tr('v2BkLoyaltyFail'), style: MgType.small.copyWith(color: MgColors.warn))),
            MgBtnText(label: tr.tr('eoRetry'), onTap: () => ref.invalidate(loyaltyStatusProvider)),
          ]),
        ],
        const SizedBox(height: 12),
        MgTotalBox(
          eyebrow: tr.totalFinal,
          value: bkMoney(bd.total),
          sub: tr.tr('priceVatNote'),
          savingsChip: bd.loyaltyDiscount > 0
              ? MgMeaningChip(
                  label: tr.trArgs('v2BkRankSaves', {'amount': bkMoney(bd.loyaltyDiscount)}),
                  tone: MgTone.ok,
                  dark: true,
                )
              : null,
        ),
      ]),
    );
  }
}
