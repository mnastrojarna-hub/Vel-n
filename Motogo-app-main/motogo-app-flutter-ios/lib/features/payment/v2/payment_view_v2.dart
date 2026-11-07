import 'package:flutter/material.dart';

import '../../../core/booking_rules.dart' show selfServiceHidesReturnTime;
import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/widgets/mg_photo_viewer.dart';
import '../../booking/booking_models.dart';
import '../../booking/v2/booking_recap_v2.dart';
import '../../booking/v2/booking_v2_parts.dart' show bkDays, bkNb;
import '../../catalog/moto_model.dart';
import '../booking_upsell_provider.dart';
import '../card_minimum.dart';
import '../payment_provider.dart';
import '../widgets/upsell_section.dart';
import 'countdown_chip_v2.dart';
import 'pay_dock_v2.dart';
import 'pay_header_v2.dart';
import 'pay_parts_v2.dart';
import 'pay_receipt_v2.dart';

/// v2 look of `PaymentScreen` (Booking board step 3 "Kontrola a platba"
/// and the board's "Režim platby" for surcharge / unfinished booking /
/// SOS / shop). Pure view: every value and callback is the screen's own
/// (amount, card-minimum charge, server-verified price, countdown text,
/// processing / expired / verifying, `_onBack`, `_doPayment`); the screen
/// keeps its back guard, timers and payment logic around it. No timer, no
/// shimmer: the static parts sit in RepaintBoundaries, so the screen's
/// 1 Hz countdown rebuild repaints only the chip.
class PaymentViewV2 extends StatelessWidget {
  final PaymentContext? ctx;
  final Motorcycle? moto;
  final BookingDraft draft;
  final PriceBreakdown breakdown;
  final List<SelectedExtra> extras;
  final List<BookingUpsellItem> bundledUpsell;
  final double amount;
  final CardCharge charge;
  final double? serverAmount;
  final bool forceMin;
  final SavedCard? defaultCard;
  final bool processing;
  final bool expired;
  final bool verifying;
  final String timeRemaining;
  final bool lastMinutes;
  final bool upsellProducts;
  final VoidCallback onBack;
  final VoidCallback onPay;

  const PaymentViewV2({
    super.key,
    required this.ctx,
    required this.moto,
    required this.draft,
    required this.breakdown,
    required this.extras,
    required this.bundledUpsell,
    required this.amount,
    required this.charge,
    required this.serverAmount,
    required this.forceMin,
    required this.defaultCard,
    required this.processing,
    required this.expired,
    required this.verifying,
    required this.timeRemaining,
    required this.lastMinutes,
    required this.upsellProducts,
    required this.onBack,
    required this.onPay,
  });

  bool get _isNew => ctx == null;

  /// A booking is paid (new, unfinished, restored, surcharge) — not SOS /
  /// e-shop: "bez kauce" and "termín ti držíme" are true only there.
  bool get _booking => ctx == null || ctx!.flowType == PaymentFlowType.booking || ctx!.flowType == PaymentFlowType.extension;

  /// SOS payment: the SOS system never carries the rank (V22 §1.4).
  bool get _sos => ctx?.flowType == PaymentFlowType.sos;

  /// The unpaid booking itself is released at the deadline.
  bool get _holds => ctx == null || ctx!.flowType == PaymentFlowType.booking;

  String? _shortId() {
    final id = ctx?.bookingId;
    if (id == null || id.length < 8) return null;
    return '#${id.substring(id.length - 8).toUpperCase()}';
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final c = ctx;
    final m = moto;
    final verified = serverAmount != null ? tr.tr('psServerPriceNote').replaceAll('{amount}', Money.czk(amount)) : null;
    final chip = PayCountdownChipV2(
      time: timeRemaining,
      expired: expired,
      processing: processing,
      warn: lastMinutes,
      holdNote: _holds,
    );
    final header = PayHeaderV2(
      title: _isNew ? tr.tr('v2BkTitle') : c!.label,
      sub: _isNew ? (m?.model ?? draft.motoName) : _shortId(),
      onBack: onBack,
      steps: _isNew,
      chip: chip,
      rank: !_sos,
    );
    final cc = cardCharge(amount, forceMin: forceMin);
    final round = cc.isRound || cc.isWaive;
    final sections = <Widget>[
      if (_isNew && m != null)
        RepaintBoundary(
          child: BookingRecapV2(
            moto: m,
            start: draft.startDate,
            end: draft.endDate,
            dayCount: breakdown.days,
            pickupTime: draft.pickupTime,
            // Self-service branch: the return time is not chosen (23:59).
            returnTime: selfServiceHidesReturnTime(branchType: m.branchType, returnMethod: draft.returnMethod)
                ? null
                : draft.returnTime,
            half: breakdown.latePickupDiscount > 0,
            pickupDelivery: draft.pickupMethod == 'delivery',
            // The old page's gallery card: every photo + branch city.
            withCity: true,
            photoCount: m.images.length,
            onPhotoTap: () => showMgPhotoViewer(context, urls: m.images.isNotEmpty ? m.images : [m.displayImage]),
          ),
        ),
      Padding(
        padding: EdgeInsets.fromLTRB(MgSpace.gutter, _isNew && m != null ? MgSpace.s12 : 0, MgSpace.gutter, 0),
        child: RepaintBoundary(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (!_isNew)
              PayReceiptV2(
                label: c!.label,
                amount: amount,
                isFree: amount <= 0,
                sosRows: c.sosBreakdown,
                depositNote: c.sosDepositNote,
                verified: verified,
              )
            else ...[
              // An applied promo / voucher stays visible before paying (the
              // old page's inline price card); the full receipt = "Rozpis".
              if (breakdown.discountTotal > 0)
                PayRowV2(
                  key: const ValueKey('pay-v2-discount'),
                  icon: MgIcons.tag,
                  label: tr.tr('discountLabel'),
                  value: '−${Money.czk(breakdown.discountTotal)}',
                  valueColor: MgColors.link,
                ),
              if (verified != null) PayVerifiedLineV2(verified),
            ],
            if (round) ...[
              const SizedBox(height: MgSpace.s12),
              PayRoundingNoteV2(due: amount, forceMin: forceMin),
            ],
            if (_isNew && m != null && upsellProducts) ...[
              const SizedBox(height: MgSpace.s12),
              UpsellSection(showProducts: upsellProducts),
            ],
            if (!charge.noCharge) ...[
              const SizedBox(height: MgSpace.s12),
              PayMethodCardV2(card: defaultCard),
            ],
            const SizedBox(height: MgSpace.s8),
            PayTrustV2(booking: _booking, showStripe: !charge.noCharge, showHold: _holds),
          ]),
        ),
      ),
    ];
    final freeLabel = (charge.isWaive ? tr.tr('pdConfirmFree') : tr.tr('confirmOrderFree')).replaceAll('→', '').trim();
    final label = expired ? tr.tr('timeExpired') : (charge.noCharge ? freeLabel : tr.tr('payBtn'));
    final contextLine = _isNew
        ? [
            tr.tr('v2YourPrice'),
            bkDays(tr, breakdown.days),
            if (breakdown.loyaltyDiscount > 0) bkNb(tr.trArgs('v2UxCbDockSaves', {'amount': Money.czk(breakdown.loyaltyDiscount)})),
          ].join(' · ')
        : '${tr.tr('v2UxPsToPay')} · ${bkNb(payAmountText(amount))}';
    final dock = PayDockV2(
      contextLine: contextLine,
      label: label,
      price: expired || charge.noCharge ? null : bkNb(Money.czk(charge.charge)),
      arrow: charge.noCharge && !expired,
      enabled: !expired,
      busy: processing,
      onPay: onPay,
      status: verifying ? tr.tr('fxVerifyingBtn') : null,
      statusNote: verifying ? tr.tr('fxVerifyingNote') : null,
      trailingLabel: _isNew ? tr.tr('v2Breakdown') : null,
      onTrailing: _isNew
          ? () => showPayBreakdownV2(context, draft: draft, breakdown: breakdown, extras: extras, upsell: bundledUpsell)
          : null,
      rank: !_sos,
    );
    return MgPage(
      header: header,
      overscrollColor: MgColors.night,
      sections: sections,
      dock: dock,
      pinnedBack: onBack,
      pinnedTitle: _isNew ? tr.tr('v2BkTitle') : c!.label,
    );
  }
}
