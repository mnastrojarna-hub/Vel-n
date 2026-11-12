import 'package:flutter/material.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_emoji_map.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../booking/booking_models.dart';
import '../../booking/v2/sections/price_v2.dart';
import '../booking_upsell_provider.dart';
import '../payment_provider.dart';
import 'pay_parts_v2.dart';

/// White receipt of a payment that is not a new booking (Booking board
/// "Režim platby": surcharge, unfinished booking, SOS, shop): the SOS rows
/// with icon tiles (when the context carries them), "K zaplacení" 15/800 +
/// the amount 26/900, "Sleva pokryla celou cenu" when free, the server-
/// verified line and the deposit note as T3 info. Values = the context's.
class PayReceiptV2 extends StatelessWidget {
  final String label;
  final double amount;
  final bool isFree;
  final List<SosPriceItem>? sosRows;
  final String? depositNote;
  final String? verified;

  const PayReceiptV2({
    super.key,
    required this.label,
    required this.amount,
    required this.isFree,
    this.sosRows,
    this.depositNote,
    this.verified,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final rows = sosRows ?? const <SosPriceItem>[];
    return PayCardV2(
      radius: MgRadius.receipt,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PayEyebrowV2(label),
        if (rows.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (final r in rows) PayRowV2(icon: payIconFor(r.icon), label: mgStripEmoji(r.label), value: Money.czk(r.amount)),
        ],
        const SizedBox(height: 6),
        const Divider(height: 1, thickness: 1, color: MgColors.line),
        const SizedBox(height: 10),
        if (isFree)
          MgTintOk(
            child: Text(mgStripEmoji(tr.tr('discountCoversAll')),
                style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onTintOk)),
          )
        else
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: MgWordFit(child: Text(tr.tr('v2UxPsToPay'), style: MgType.title.copyWith(color: MgColors.ink)))),
            const SizedBox(width: 10),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: Text(payAmountText(amount),
                    maxLines: 1,
                    style: MgType.tab(MgType.h1.copyWith(fontSize: 26, fontWeight: FontWeight.w900, color: MgColors.ink))),
              ),
            ),
          ]),
        if (verified != null) ...[const SizedBox(height: 8), PayVerifiedLineV2(verified!)],
        if (depositNote != null) ...[
          const SizedBox(height: MgSpace.s12),
          MgStateBanner(tone: MgTone.info, title: mgStripEmoji(depositNote!)),
        ],
      ]),
    );
  }
}

/// The price card of a new booking, INLINE as the old `PriceSummaryCard`:
/// the booking form's own v2 receipt (same rows and conditions); a bundled
/// e-shop add-on is listed under it with the total incl. it.
class PayBreakdownV2 extends StatelessWidget {
  final BookingDraft draft;
  final PriceBreakdown breakdown;
  final List<SelectedExtra> extras;
  final List<BookingUpsellItem> upsell;
  const PayBreakdownV2({
    super.key,
    required this.draft,
    required this.breakdown,
    required this.extras,
    required this.upsell,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final upsellTotal = upsell.fold<double>(0, (s, i) => s + i.price);
    return Column(key: const ValueKey('pay-v2-breakdown'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      BookingPriceV2(draft: draft, bd: breakdown, dayCount: breakdown.days, pricedExtras: extras, margin: EdgeInsets.zero),
      if (upsell.isNotEmpty) ...[
        const SizedBox(height: MgSpace.s12),
        PayCardV2(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final u in upsell) PayRowV2(label: u.name, value: '+${Money.czk(u.price)}'),
            const Divider(height: 12, color: MgColors.line),
            PayRowV2(label: tr.tr('totalLabel'), value: Money.czk(breakdown.total + upsellTotal)),
          ]),
        ),
      ],
    ]);
  }
}
