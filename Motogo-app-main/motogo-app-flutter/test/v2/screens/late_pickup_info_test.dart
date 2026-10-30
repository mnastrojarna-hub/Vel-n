// Owner 2026-10-22: "vyzvednutí od 12:00" is INFORMATION before the booking
// form (no toggle, standard price + the concrete saving), and the booking
// form's time card is the one place where the time is chosen — with the
// concrete ½ discount next to the time and "Nastavit 12:00" = the same
// draft write as the time dropdown.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/booking_form_widget.dart';
import 'package:motogo_app/core/currency.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/widgets/mg_chips.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/booking/booking_provider.dart';
import 'package:motogo_app/features/booking/booking_quote.dart';
import 'package:motogo_app/features/booking/v2/sections/time_v2.dart' show lateSaving;
import 'package:motogo_app/features/catalog/v2/calc/calc_state.dart';
import 'package:motogo_app/features/catalog/v2/catalog_mode.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';
import 'package:motogo_app/features/home/v2/funnel_provider.dart';
import 'package:motogo_app/features/home/v2/home_offer_block_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_booking.dart';
import '../support/fakes_catalog.dart' show catalogOverrides;
import '../support/fakes_home.dart' as fh;
import '../support/v2_harness.dart';

String _cs(String key, [Map<String, String> args = const {}]) {
  var s = translations['cs']![key]!;
  args.forEach((k, v) => s = s.replaceAll('{$k}', v));
  return s;
}

Finder _timeChip() =>
    find.byWidgetPredicate((w) => w is MgChoiceChip && (w.label == '09:00' || w.label == '12:00'));

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerCatalogStrings();
    registerBookingStrings();
    mockBookingPathProvider();
  });
  setUp(() {
    MgMotion.resetSession();
    SharedPreferences.setMockInitialValues({});
  });

  final (ws, we) = futureWeekend();
  final calcMode = catalogCalcRequestProvider.overrideWith((ref) => true);

  group('calculator', () {
    testWidgets('no time choice; standard price + the concrete 12:00 saving as info', (t) async {
      await pumpV2(t, const MotorkyScreenV2(),
          size: const Size(412, 4200),
          overrides: [...catalogOverrides(calc: CalcState(motoId: 'm-bmw', start: ws, end: we)), calcMode]);
      await t.pump();
      await t.pump(const Duration(milliseconds: 800));
      final q = quoteFor(kBmw, ws, we, loyalty: kLoyalty3);
      final q12 = quoteFor(kBmw, ws, we, pickupTime: '12:00', loyalty: kLoyalty3);
      expect(q.total, greaterThan(q12.total));
      expect(_timeChip(), findsNothing);
      expect(find.text(_cs('v2LpCalcHandover')), findsOneWidget);
      expect(find.text(_cs('v2LpCalcTitle')), findsOneWidget);
      expect(
          find.text(_cs('v2LpCalcSave', {'amount': Money.czk(q.total - q12.total), 'total': Money.czk(q12.total)})),
          findsOneWidget);
      expect(find.text(_cs('v2CalcLateSet')), findsNothing);
      // The price (and REZERVOVAT) is the standard pickup price.
      expect(find.byWidgetPredicate((w) => w is MgCta && w.price == Money.czk(q.total)), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
    });

    testWidgets('1-day trip: general note, no saving card', (t) async {
      await pumpV2(t, const MotorkyScreenV2(),
          size: const Size(412, 4200),
          overrides: [...catalogOverrides(calc: CalcState(motoId: 'm-bmw', start: ws, end: ws)), calcMode]);
      await t.pump(const Duration(milliseconds: 600));
      expect(_timeChip(), findsNothing);
      expect(find.text(_cs('v2CalcLateOne')), findsOneWidget);
      expect(find.text(_cs('v2LpCalcTitle')), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
    });
  });

  testWidgets('Home offer: the centred bike saving, not a price to choose', (t) async {
    final two = fh.kMotos.take(2).toList();
    await pumpV2(t, const SingleChildScrollView(child: HomeOfferBlockV2()),
        size: const Size(412, 900), overrides: fh.homeOverrides(funnel: two));
    await t.pump(const Duration(milliseconds: 600));
    final r = funnelPresets(DateTime.now()).$1;
    final m = two.first;
    final std = quoteFor(m, r.start, r.end, loyalty: fh.kLoyalty3).total;
    final late = quoteFor(m, r.start, r.end, pickupTime: '12:00', loyalty: fh.kLoyalty3).total;
    expect(find.text(_cs('v2LpHomeSave', {'bike': m.model, 'amount': Money.czk(std - late)})), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
  });

  group('booking form time card', () {
    Future<ProviderContainer> pumpForm(WidgetTester t, List<Override> overrides) async {
      await pumpV2(t, const BookingDebugWrapper(), size: const Size(412, 915), overrides: overrides);
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      return ProviderScope.containerOf(t.element(find.byType(BookingDebugWrapper)));
    }

    // r2: the ½ row shows the SAME saving the calculator / Home promise
    // (standard − 12:00 total, both with the rank discount); the gross
    // "Sleva 50 % na 1. den" stays in the price summary.
    testWidgets('09:00 → the calculator\'s saving; "Nastavit 12:00" writes the draft like the dropdown', (t) async {
      final c = await pumpForm(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw)));
      final (s, e) = futureWeekend();
      final half = quoteFor(kBmw, s, e, pickupTime: '12:00').latePickupDiscount;
      final q = quoteFor(kBmw, s, e, loyalty: kLoyalty3);
      final q12 = quoteFor(kBmw, s, e, pickupTime: '12:00', loyalty: kLoyalty3);
      final save = lateSaving(q, q12);
      expect(save, q.total - q12.total);
      expect(save, greaterThan(0));
      // With a rank the net saving is smaller than the gross half day.
      expect(save, lessThan(half));
      final offer = find.text(_cs('v2LpFormSaveNet', {'amount': Money.czk(save)}));
      expect(offer, findsOneWidget);
      expect(find.text(_cs('v2LpFormSave', {'amount': Money.czk(half)})), findsNothing);
      expect(find.text(_cs('v2LpSsHint')), findsNothing);
      final set = find.text(_cs('v2CalcLateSet'));
      // Mid-viewport: at the top edge it would sit under the pinned back bar.
      await Scrollable.ensureVisible(t.element(set), alignment: 0.4);
      await t.pump();
      await t.tap(set);
      await t.pump(const Duration(milliseconds: 400));
      expect(c.read(bookingDraftProvider).pickupTime, '12:00');
      expect(c.read(priceBreakdownProvider).latePickupDiscount, half);
      expect(c.read(priceBreakdownProvider).total, q12.total);
      expect(find.text(_cs('v2LpFormOnNet', {'amount': Money.czk(save)})), findsOneWidget);
      expect(find.text(_cs('v2CalcLateSet')), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
    });

    testWidgets('self-service: ½ row + the kiosk note', (t) async {
      await pumpForm(t, bookingOverrides(moto: kHusq, draft: bookingDraft(kHusq, pickupTime: '12:00')));
      final (s, e) = futureWeekend();
      final save = lateSaving(
          quoteFor(kHusq, s, e, loyalty: kLoyalty3), quoteFor(kHusq, s, e, pickupTime: '12:00', loyalty: kLoyalty3));
      expect(find.text(_cs('v2LpFormOnNet', {'amount': Money.czk(save)})), findsOneWidget);
      expect(find.text(_cs('v2LpSsHint')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
    });

    testWidgets('1-day trip: the general hint, no quick set', (t) async {
      final d = bookingDraft(kBmw);
      await pumpForm(t, bookingOverrides(moto: kBmw, draft: d.copyWith(endDate: () => d.startDate)));
      expect(find.text(_cs('latePickupHint12')), findsOneWidget);
      expect(find.text(_cs('v2CalcLateSet')), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
    });
  });
}
