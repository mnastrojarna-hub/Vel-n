import 'package:flutter/material.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../payment/widgets/card_rounding_note.dart';
import '../reservation_edit_price_calc.dart';
import '../reservation_models.dart';
import 'res_fit_v2.dart';

/// "Rozdíl ceny" of the edit (V22 `.ed-rc`): the SAME lines under the SAME
/// conditions as today's price overview, fed by the screen's
/// `EditPriceCalc` (no maths here), and the result in a dark total box
/// (Doplatek / Vrácení / Rozdíl) with today's card-minimum note and the
/// storno % line.
class ResEditPriceV2 extends StatelessWidget {
  final Reservation booking;
  final EditPriceCalc calc;
  const ResEditPriceV2({super.key, required this.booking, required this.calc});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    String days(int n) => '$n ${tr.daysWord(n)}';
    final diff = calc.effectivePriceDiff;
    final rows = <(String, String)>[
      (tr.tr('originalPrice'), Money.czk(booking.totalPrice)),
      (tr.tr('originalDuration'), days(calc.origDays)),
      if (calc.diffDays != 0) (tr.tr('newDuration'), days(calc.newDays)),
      if (calc.diffDays > 0)
        ('${tr.tr('extensionLabel')} (+${days(calc.diffDays)})', '+${Money.czk(calc.dateChangeAmount)}'),
      if (calc.diffDays < 0)
        ('${tr.tr('shorteningLabel')} (${days(calc.diffDays.abs())})', '-${Money.czk(calc.dateChangeAmount.abs())}'),
      if (calc.latePickupDelta != 0)
        (tr.tr('latePickupDiscountLabel'), '${calc.latePickupDelta > 0 ? "+" : "−"}${Money.czk(calc.latePickupDelta.abs())}'),
      if (calc.deliveryFeeDelta != 0)
        ('${tr.tr('pickupDeliveryLabel')} / ${tr.tr('returnDeliveryLabel')}',
            '${calc.deliveryFeeDelta > 0 ? "+" : "−"}${Money.czk(calc.deliveryFeeDelta.abs())}'),
      if (calc.extrasTotal > 0) (tr.tr('addons'), '+${Money.czk(calc.extrasTotal)}'),
      if ((booking.discountAmount ?? 0) > 0 && calc.newDiscountAmount != (booking.discountAmount ?? 0))
        (tr.tr('discountLabel'), '${(booking.discountAmount ?? 0).toStringAsFixed(0)} → ${Money.czk(calc.newDiscountAmount)}'),
    ];
    final totalLabel = diff > 0
        ? tr.tr('surcharge')
        : diff < 0
            ? tr.tr('refundLabel')
            : tr.tr('differenceLabel');
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MgColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MgColors.line),
        boxShadow: MgShadows.card,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MgEyebrow(tr.tr('differenceLabel'), dark: false),
        const SizedBox(height: 4),
        for (final r in rows)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: MgColors.line))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(r.$1, style: MgType.small.copyWith(color: MgColors.body2))),
              const SizedBox(width: 12),
              Text(r.$2, style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink))),
            ]),
          ),
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(gradient: MgGradients.darkCta, borderRadius: BorderRadius.circular(14)),
          // Popisek vedle částky, jen když se vejde celým slovem (de
          // „RÜCKERSTATTUNG", fr „REMBOURSEMENT" na 320 dp) — jinak nad ní.
          child: LayoutBuilder(builder: (context, c) {
            final amountText = '${diff > 0 ? "+" : ""}${Money.czk(diff)}';
            final amountStyle = MgType.tab(MgType.h2.copyWith(
                color: diff > 0 ? MgColors.errDark : diff < 0 ? MgColors.neon : MgColors.onDark));
            final labelStyle = MgType.eyebrow.copyWith(color: MgColors.neonText);
            final label = MgWordFit(minScale: 0.85, child: Text(totalLabel.toUpperCase(), style: labelStyle));
            final amount = MgBump(trigger: diff.round(), child: Text(amountText, style: amountStyle));
            final inline = resWordsFit(context, totalLabel.toUpperCase(), labelStyle,
                c.maxWidth - 12 - resLineWidth(context, amountText, amountStyle), minScale: 0.85);
            if (inline) {
              return Row(children: [Expanded(child: label), const SizedBox(width: 12), amount]);
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              label,
              const SizedBox(height: 4),
              Align(alignment: AlignmentDirectional.centerEnd, child: amount),
            ]);
          }),
        ),
        // Minimum karty (D1): doplatek 1–15 Kč → kartou 15 Kč; do 1 Kč bez platby.
        if (diff > 0)
          CardRoundingNote(due: diff, roundKey: 'pdRoundEditHint', waiveKey: 'pdWaiveEditHint', showLine: false),
        // i při 0 Kč: pozdější čas ve stornu → sleva přiznaná jen z části
        if (calc.datesDiffRaw < 0 && (diff < 0 || calc.stornoPercent < 100))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(tr.tr('stornoRefundPercent').replaceAll('{percent}', '${calc.stornoPercent}'),
                style: MgType.meta.copyWith(color: MgColors.meta)),
          ),
      ]),
    );
  }
}
