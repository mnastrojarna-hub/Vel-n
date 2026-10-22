import 'package:flutter/material.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_animated_size.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../reservation_models.dart';
import '../widgets/res_payment_details_tab.dart';
import 'res_status_v2.dart';

/// "Peníze" (white card): the same lines as today's Finanční souhrn
/// (total, delivery, extras, ½ first-day discount, discount + code, payment
/// status — translated, never the raw DB value) and "Podrobnosti o platbě"
/// (today's second tab) as an expander with `ResPaymentDetailsTab` inside.
class ResMoneyV2 extends StatefulWidget {
  final Reservation res;
  const ResMoneyV2({super.key, required this.res});

  @override
  State<ResMoneyV2> createState() => _ResMoneyV2State();
}

class _ResMoneyV2State extends State<ResMoneyV2> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final res = widget.res;
    final paid = res.paymentStatus == 'paid' && res.status != 'cancelled';
    final unpaid = res.paymentStatus == 'unpaid';
    return MgCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MgEyebrow(tr.tr('financialSummary'), dark: false),
        const SizedBox(height: 12),
        Text(tr.tr('totalPrice'), style: MgType.meta.copyWith(color: MgColors.meta)),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(Money.czk(res.totalPrice), style: MgType.tab(MgType.display.copyWith(fontSize: 30, color: MgColors.ink))),
            _payPill(resPayStatusLabel(tr, res), paid: paid, unpaid: unpaid),
          ],
        ),
        const SizedBox(height: 8),
        if (res.deliveryFee != null && res.deliveryFee! > 0) _row(tr.tr('deliveryFee'), Money.czk(res.deliveryFee!)),
        if (res.extrasPrice != null && res.extrasPrice! > 0) _row(tr.tr('addons'), Money.czk(res.extrasPrice!)),
        if ((res.latePickupDiscount ?? 0) > 0)
          _row(tr.tr('latePickupDiscountLabel'), '−${Money.czk(res.latePickupDiscount!)}', ok: true),
        if (res.discountAmount != null && res.discountAmount! > 0)
          _row('${tr.tr('discountLabel')} ${res.discountCode ?? ''}'.trim(), '−${Money.czk(res.discountAmount!)}', ok: true),
        const SizedBox(height: 4),
        Semantics(
          button: true,
          expanded: _open,
          label: tr.tr('paymentDetailsTab'),
          excludeSemantics: true,
          child: MgPress(
            onTap: () => setState(() => _open = !_open),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(children: [
                Flexible(
                  child: Text(tr.tr('paymentDetailsTab'),
                      style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.link)),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: MgMotion.of(context, MgMotion.pop),
                  child: const MgIcon(MgIcons.chevronDown, size: 18, color: MgColors.link),
                ),
              ]),
            ),
          ),
        ),
        MgAnimatedSize(
          duration: MgMotion.pop,
          curve: MgMotion.out,
          alignment: Alignment.topCenter,
          child: _open ? ResPaymentDetailsTab(res: res) : const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }

  Widget _payPill(String label, {required bool paid, required bool unpaid}) {
    final (Color bg, Color fg, Color border) = paid
        ? (MgColors.tintOk, MgColors.onTintOk, MgColors.tintOkBorder)
        : unpaid
            ? (MgColors.warnBg, MgColors.warn, MgColors.warnBorder)
            : (MgColors.well, MgColors.ink, MgColors.line);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999), border: Border.all(color: border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (paid) ...[const MgIcon(MgIcons.check, size: 14, color: MgColors.link, stroke: 2.6), const SizedBox(width: 4)],
        Flexible(
          child: Text(label,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: MgType.meta.copyWith(fontWeight: FontWeight.w800, color: fg)),
        ),
      ]),
    );
  }

  Widget _row(String label, String value, {bool ok = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: MgColors.line))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(label, style: MgType.small.copyWith(color: MgColors.body2))),
          const SizedBox(width: 12),
          Text(value, style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: ok ? MgColors.link : MgColors.ink))),
        ]),
      );
}
