import 'package:flutter/material.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/calendar/trip_day_state.dart' show tripDate;
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/icons/mg_icons.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../booking/booking_models.dart';
import '../../booking/v2/booking_v2_parts.dart' show bkDays, bkNb;
import '../../catalog/moto_model.dart';
import '../booking_upsell_provider.dart';
import '../card_minimum.dart';
import '../payment_provider.dart';
import '../widgets/upsell_section.dart';
import 'countdown_chip_v2.dart';
import 'pay_dock_v2.dart';
import 'pay_gallery_v2.dart';
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

  /// J8: "{model} · 11. 12.–13. 12. 2026" — the rental dates stay in
  /// view on the pay step (draft data, display only).
  String? _newSub(AppTranslations tr) {
    final model = moto?.model ?? draft.motoName;
    final s = draft.startDate;
    final e = draft.endDate;
    if (s == null || e == null) return model;
    final from = tr.trArgs('v2CalDateShort', {'d': s.day, 'm': s.month});
    // The range never splits (no-break spaces, word joiners at the dash).
    final range = '$from\u2060–\u2060${tripDate(tr, e)}'.replaceAll(' ', '\u00A0');
    return [if (model != null) model, range].join(' · ');
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
      sub: _isNew ? _newSub(tr) : _shortId(),
      onBack: onBack,
      chip: chip,
      rank: !_sos,
    );
    final cc = cardCharge(amount, forceMin: forceMin);
    final round = cc.isRound || cc.isWaive;
    final sections = <Widget>[
      // The old page's MotoGalleryCard: inline pager of every photo, the
      // model and "{branch}, {city}".
      if (_isNew && m != null)
        RepaintBoundary(
          child: PayGalleryV2(
            images: m.images.isNotEmpty ? m.images : [m.displayImage],
            model: m.model,
            branchName: m.branchName,
            branchCity: m.branchCity,
          ),
        ),
      Padding(
        padding: EdgeInsets.fromLTRB(MgSpace.gutter, _isNew && m != null ? MgSpace.s12 : 0, MgSpace.gutter, 0),
        child: RepaintBoundary(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // E3-08: an edit surcharge — the change applies only once paid.
            if (c?.flowType == PaymentFlowType.extension) ...[
              MgStateBanner(
                key: const ValueKey('pay-surcharge-after'),
                tone: MgTone.info,
                icon: MgIcons.info,
                title: tr.tr('efoSurchargeAfterPay'),
              ),
              const SizedBox(height: MgSpace.s12),
            ],
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
              // The old page's PriceSummaryCard, open inline: the booking
              // form's v2 receipt (same rows and conditions) + a bundled
              // e-shop add-on with the total incl. it.
              PayBreakdownV2(draft: draft, breakdown: breakdown, extras: extras, upsell: bundledUpsell),
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
        ? [tr.tr('v2YourPrice'), bkDays(tr, breakdown.days)].join(' · ')
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
