// lookonly-fix:areas (owner 2026-11-07 "jen upgrade vzhledu"): Profil,
// payment, e-shop, SOS and Trasy in the v2 look keep the original content,
// order, defaults and entry points (no new shortcuts, nothing hidden).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/chrome/mg_ai_fab.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/booking/v2/booking_header_v2.dart';
import 'package:motogo_app/features/payment/card_minimum.dart';
import 'package:motogo_app/features/payment/v2/pay_gallery_v2.dart';
import 'package:motogo_app/features/payment/v2/pay_receipt_v2.dart';
import 'package:motogo_app/features/payment/v2/payment_view_v2.dart';
import 'package:motogo_app/features/payment/v2/upsell_row_v2.dart';
import 'package:motogo_app/features/profile/v2/profile_attention_v2.dart';
import 'package:motogo_app/features/routes/v2/record_dock_v2.dart';
import 'package:motogo_app/features/routes/v2/route_detail_parts_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/moje_tabs_v2.dart';
import 'package:motogo_app/features/sos/v2/sos_start_view_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../render/cases_ux_pay_shop.dart' show kPsCards, kPsProducts;
import '../screens/rides_cases.dart';
import '../render/cases_ux_auth_sos_misc.dart' show asmBase;
import '../support/fakes_booking.dart';
import '../support/fakes_profile.dart';
import '../support/fakes_rides.dart';
import '../support/profile_harness.dart';
import '../support/ps_harness.dart';
import '../support/v2_harness.dart';

String _cs(String key) => AppTranslations.of('cs').tr(key);
void _n() {}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    mockBookingPathProvider();
  });
  setUp(() {
    MgMotion.resetSession();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Profil: the old order and entry points (no attention chips, AI row, gear; back always)', (t) async {
    await pumpV2(t, const PfHubHarness(), size: const Size(412, 4000), overrides: profileOverrides(), reducedMotion: true);
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(ProfileAttentionV2), findsNothing);
    expect(find.text(_cs('aiServiceAgent')), findsNothing);
    expect(find.byKey(const ValueKey('pf-back')), findsOneWidget);
    // Section labels are drawn in caps → match case-insensitively.
    double y(String key) =>
        t.getTopLeft(find.textContaining(RegExp('^${RegExp.escape(_cs(key))}\$', caseSensitive: false)).first).dy;
    // Pobočky above "Můj účet"; Osobní údaje first in it, then Zprávy … Platební metody.
    expect(y('branchesLabel'), lessThan(y('myAccount')));
    expect(y('myAccount'), lessThan(y('personalInfo')));
    expect(y('personalInfo'), lessThan(y('messages')));
    expect(y('messages'), lessThan(y('paymentMethods')));
    expect(y('paymentMethods'), lessThan(y('settings')));
    await t.pump(const Duration(seconds: 2));
  });

  group('payment (new booking)', () {
    PaymentViewV2 view() => PaymentViewV2(
          ctx: null,
          moto: kBmw,
          draft: bookingDraft(kBmw),
          breakdown: const PriceBreakdown(
              basePrice: 10504, extrasTotal: 0, pickupDeliveryFee: 0, returnDeliveryFee: 0, discountTotal: 0, total: 10189, days: 3, loyaltyDiscount: 315),
          extras: const [],
          bundledUpsell: const [],
          amount: 10189,
          charge: cardCharge(10189),
          serverAmount: null,
          forceMin: false,
          defaultCard: kPsCards.first,
          processing: false,
          expired: false,
          verifying: false,
          timeRemaining: '29:59',
          lastMinutes: false,
          upsellProducts: false,
          onBack: () {},
          onPay: () {},
        );

    testWidgets('inline photo pager + the full price card open; no "Rozpis" link, no step bar', (t) async {
      await pumpV2(t, view(), size: const Size(412, 3000), scaffold: false, overrides: bookingOverrides(moto: kBmw));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(PayGalleryV2), findsOneWidget);
      expect(find.descendant(of: find.byType(PayGalleryV2), matching: find.byType(PageView)), findsOneWidget);
      expect(find.textContaining('Mezná, Pelhřimov'), findsOneWidget);
      expect(find.byType(PayBreakdownV2), findsOneWidget);
      expect(find.text(_cs('v2Breakdown')), findsNothing);
      expect(find.byType(BookingStepsV2), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 4));
    });

    testWidgets('upsell: all featured products one under another (no swipe row)', (t) async {
      await pumpPs(
        t,
        Material(
          child: SingleChildScrollView(
            child: UpsellRowV2(
              products: kPsProducts.take(3).toList(),
              isSelected: (_) => false,
              sizeOf: (_) => null,
              onToggle: (_, __) {},
              onRemove: (_) {},
            ),
          ),
        ),
        size: const Size(412, 1400),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('upsell-v2-row')), findsNothing);
      for (final p in kPsProducts.take(3)) {
        expect(find.byKey(ValueKey('upsell-v2-${p.id}')), findsOneWidget);
        expect(t.getRect(find.byKey(ValueKey('upsell-v2-${p.id}'))).right, lessThanOrEqualTo(412));
      }
      expect(find.text(_cs('recommendForBooking')), findsOneWidget);
    });
  });

  testWidgets('SOS start: the old order — AI agent before 112 / 155 / 158; no booking eyebrow', (t) async {
    await pumpV2(
        t,
        SosStartViewV2(
            active: const AsyncValue.data(null),
            onBack: _n,
            onAccident: _n,
            onBreakdown: _n,
            onShareLocation: _n,
            onAi: _n,
            onOpenIncident: _n,
            onDial: (_) {}),
        size: const Size(412, 2400),
        scaffold: false,
        overrides: asmBase());
    await t.pump(const Duration(milliseconds: 100));
    double y(Finder f) => t.getTopLeft(f.first).dy;
    expect(y(find.text('AI Servisní agent')), lessThan(y(find.text('112'))));
    expect(y(find.text('112')), lessThan(y(find.text('Nehoda / Krádež'))));
  });

  group('Trasy', () {
    testWidgets('route description is shown in full (no "více" toggle)', (t) async {
      final long = List.filled(30, 'Krásná vyhlídková trasa přes kopce a lesy.').join(' ');
      await pumpV2(t, SingleChildScrollView(child: RouteDescV2(long)), size: const Size(360, 3000));
      expect(t.widget<Text>(find.byKey(const ValueKey('rt-desc'))).maxLines, isNull);
      expect(find.text(_cs('v2RtMore')), findsNothing);
    });

    testWidgets('Moje: the old three tabs; rides AND saved routes on the first page', (t) async {
      await pumpV2(t, mojeView(), overrides: ridesOverrides(), scaffold: false, reducedMotion: true, size: const Size(412, 6000));
      await t.pump(const Duration(milliseconds: 600));
      final chips = find.descendant(of: find.byType(MojeSubChipsV2), matching: find.text(_cs('v2RideSubSaved')));
      expect(chips, findsNothing);
      expect(find.descendant(of: find.byType(MojeSubChipsV2), matching: find.text(_cs('myExpRoutesTab'))), findsOneWidget);
      expect(find.byKey(const ValueKey('moje-saved-head')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
    });

    testWidgets('record dock: ZAZNAMENAT JÍZDU without a docked AI disc', (t) async {
      await pumpV2(t, TrasyRecordDockV2(onOpenRecorder: () {}), overrides: ridesOverrides());
      await t.pump();
      expect(find.byWidgetPredicate((w) => w is MgCta && w.label == _cs('v2RtRecShort')), findsOneWidget);
      expect(find.byType(MgAiDisc), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
    });
  });
}
