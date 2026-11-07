// pay_shop PS-01 / 02 / 18 / 19: the v2 payment page — seam wiring, the
// same pay handler, expired / busy / free blockers, countdown chip states,
// receipt modes, the "Rozpis" sheet and at most one ticker while idle.
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/booking/v2/booking_header_v2.dart';
import 'package:motogo_app/features/booking/v2/sections/price_v2.dart';
import 'package:motogo_app/features/payment/card_minimum.dart';
import 'package:motogo_app/features/payment/payment_provider.dart';
import 'package:motogo_app/features/payment/payment_screen.dart';
import 'package:motogo_app/features/payment/v2/countdown_chip_v2.dart';
import 'package:motogo_app/features/payment/v2/pay_receipt_v2.dart';
import 'package:motogo_app/features/payment/v2/payment_view_v2.dart';
import 'package:motogo_app/features/payment/widgets/payment_header_widgets.dart';

import '../render/cases_ux_pay_shop.dart' show kPsCards, psPayOverrides;
import '../support/fakes_booking.dart';
import '../support/ps_harness.dart';
import '../support/v2_harness.dart' show pumpV2;

PaymentViewV2 _view({
  PaymentContext? ctx,
  double amount = 10189,
  bool expired = false,
  bool processing = false,
  bool verifying = false,
  bool lastMinutes = false,
  required VoidCallback onPay,
}) =>
    PaymentViewV2(
      ctx: ctx,
      moto: ctx == null ? kBmw : null,
      draft: bookingDraft(kBmw),
      breakdown: const PriceBreakdown(
          basePrice: 10504, extrasTotal: 0, pickupDeliveryFee: 0, returnDeliveryFee: 0, discountTotal: 0, total: 10189, days: 3, loyaltyDiscount: 315),
      extras: const [],
      bundledUpsell: const [],
      amount: amount,
      charge: cardCharge(amount),
      serverAmount: null,
      forceMin: false,
      defaultCard: kPsCards.first,
      processing: processing,
      expired: expired,
      verifying: verifying,
      timeRemaining: '29:59',
      lastMinutes: lastMinutes,
      upsellProducts: false,
      onBack: () {},
      onPay: onPay,
    );

void main() {
  setUpAll(mockBookingPathProvider);

  testWidgets('flag ON: /payment shows the v2 view (step 3 header, chip, CTA); OFF the old screen', (tester) async {
    var router = await pumpPs(tester, const PaymentScreen(), overrides: psPayOverrides());
    expect(find.byType(PaymentViewV2), findsOneWidget);
    expect(find.byType(BookingStepsV2), findsOneWidget);
    expect(find.byType(PayCountdownChipV2), findsOneWidget);
    expect(find.byType(PaymentHeader), findsNothing);
    await psLeaveRoute(tester, router);
    router = await pumpPs(tester, const PaymentScreen(), overrides: psPayOverrides(), v2: false);
    expect(find.byType(PaymentViewV2), findsNothing);
    expect(find.byType(PaymentHeader), findsOneWidget);
    await psLeaveRoute(tester, router);
  });

  testWidgets('the CTA runs the screen\'s pay handler once; expired / busy lock it', (tester) async {
    var paid = 0;
    await pumpV2(tester, _view(onPay: () => paid++), scaffold: false);
    await tester.tap(find.byKey(const ValueKey('pay-v2-cta')));
    await tester.pump();
    expect(paid, 1);
    expect(tester.widget<MgCta>(find.byKey(const ValueKey('pay-v2-cta'))).price, contains('10'));

    await pumpV2(tester, _view(expired: true, onPay: () => paid++), scaffold: false);
    final cta = tester.widget<MgCta>(find.byKey(const ValueKey('pay-v2-cta')));
    expect(cta.enabled, isFalse);
    expect(cta.price, isNull);
    await tester.tap(find.byKey(const ValueKey('pay-v2-cta')), warnIfMissed: false);
    expect(paid, 1);

    await pumpV2(tester, _view(processing: true, verifying: true, onPay: () => paid++), scaffold: false);
    expect(tester.widget<MgCta>(find.byKey(const ValueKey('pay-v2-cta'))).busy, isTrue);
    await tester.tap(find.byKey(const ValueKey('pay-v2-cta')), warnIfMissed: false);
    expect(paid, 1);
    expect(find.text('Ověřujeme platbu…'), findsWidgets);
  });

  testWidgets('free / waived amount: confirm label without a price, same handler', (tester) async {
    var paid = 0;
    await pumpV2(tester, _view(amount: 0.4, onPay: () => paid++), scaffold: false);
    final cta = tester.widget<MgCta>(find.byKey(const ValueKey('pay-v2-cta')));
    expect(cta.price, isNull);
    expect(cta.label.contains('→'), isFalse);
    await tester.tap(find.byKey(const ValueKey('pay-v2-cta')));
    expect(paid, 1);
  });

  testWidgets('countdown chip: normal / last 5 min / paying / expired', (tester) async {
    Future<void> chip({bool warn = false, bool busy = false, bool exp = false}) => pumpV2(
        tester, PayCountdownChipV2(time: '4:59', expired: exp, processing: busy, warn: warn, holdNote: true));
    await chip();
    expect(find.text('Zbývá 4:59 na zaplacení'), findsOneWidget);
    expect(find.text('termín ti zatím držíme'), findsOneWidget);
    await chip(warn: true);
    expect(find.text('Zbývá 4:59 — dokonči platbu'), findsOneWidget);
    await chip(busy: true);
    expect(find.text('Platba probíhá…'), findsOneWidget);
    await chip(exp: true);
    expect(find.text('Čas vypršel'), findsOneWidget);
  });

  testWidgets('surcharge mode: what is paid in the header + #number, receipt, no Rozpis', (tester) async {
    final ctx = PaymentContext(
        flowType: PaymentFlowType.extension, bookingId: 'aaaa-bbbb-8f3a2c1d', amount: 3408, label: 'Doplatek za prodloužení');
    await pumpV2(tester, _view(ctx: ctx, amount: 3408, onPay: () {}), scaffold: false);
    expect(find.text('#8F3A2C1D'), findsOneWidget);
    expect(find.byType(PayReceiptV2), findsOneWidget);
    expect(find.text('K zaplacení'), findsWidgets);
    expect(find.text('Rozpis'), findsNothing);
  });

  testWidgets('"Rozpis" opens the booking receipt in a sheet', (tester) async {
    await pumpV2(tester, _view(onPay: () {}), scaffold: false, overrides: bookingOverrides(moto: kBmw));
    await tester.tap(find.text('Rozpis'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(BookingPriceV2), findsOneWidget);
  });

  testWidgets('PS-19: idle page runs at most one ticker (the CTA fx)', (tester) async {
    await pumpV2(tester, _view(onPay: () {}), scaffold: false);
    // Real frames (a single long pump would only start the one-shots).
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(SchedulerBinding.instance.transientCallbackCount, lessThanOrEqualTo(1));
  });
}
