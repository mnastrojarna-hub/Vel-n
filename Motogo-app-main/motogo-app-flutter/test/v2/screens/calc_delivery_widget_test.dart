// Calculator with delivery (owner 2026-11-27) — step ④ on the real Motorky
// screen: an eligible bike gets the booking form's own option rows, address
// sheet, route fee, receipt line and total (pickup and return side); a
// self-service bike shows the form's locked tiles; switching to it after an
// address was entered drops the delivery; a start within the 6 h lead time
// shows the form's own message. The booking form's providers stay untouched.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/booking_address_carry.dart';
import 'package:motogo_app/core/booking_form_locked_option.dart';
import 'package:motogo_app/core/currency.dart';
import 'package:motogo_app/core/feature_flags.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/booking/booking_provider.dart';
import 'package:motogo_app/features/booking/booking_quote.dart';
import 'package:motogo_app/features/booking/v2/booking_v2_parts.dart';
import 'package:motogo_app/features/booking/v2/sections/price_v2.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_parts_v2.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_receipt_v2.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_state.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_step_handover_v2.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_total_v2.dart';
import 'package:motogo_app/features/catalog/v2/catalog_mode.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_booking.dart';
import '../support/fakes_calc_delivery.dart';
import '../support/fakes_catalog.dart' show catalogOverrides;
import '../support/v2_harness.dart';

String _cs(String key) => translations['cs']![key]!;

Future<ProviderContainer> _pumpCalc(WidgetTester t, CalcState st,
    {bool reducedMotion = false, bool selfServiceDelivery = false}) async {
  await pumpV2(t, const MotorkyScreenV2(),
      size: const Size(412, 4600),
      reducedMotion: reducedMotion,
      overrides: [
        ...catalogOverrides(calc: st, profile: kProfileJihlava),
        catalogCalcRequestProvider.overrideWith((ref) => true),
        selfServiceDeliveryEnabledProvider.overrideWith((ref) async => selfServiceDelivery),
      ]);
  await _steps(t, 3);
  return ProviderScope.containerOf(t.element(find.byType(MotorkyScreenV2)));
}

Future<void> _steps(WidgetTester t, int n) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.tap(f);
  await _steps(t, 3);
}

Future<void> _unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 2));
}

Finder _in(Type scope, Finder f) => find.descendant(of: find.byType(scope), matching: f);

/// The option row with [title] inside the pickup (0) / return (1) section.
Finder _opt(String title) => find.byWidgetPredicate((w) => w is BkOptionRow && w.title == title);

bool _price(WidgetTester t, double total) =>
    t.widgetList<MgCta>(_in(CalcTotalV2, find.byType(MgCta))).single.price == Money.czk(total);

/// Opens the address sheet of the first empty address row and confirms the
/// profile address (one-tap quick option → geocode → route → POTVRDIT).
Future<void> _enterProfileAddress(WidgetTester t) async {
  await _tap(t, find.text(_cs('v2BkEnterAddress')).first);
  await _tap(t, find.text(_cs('bkAddrMine')));
  expect(find.text('~${kRouteKm.toStringAsFixed(0)} km · ${Money.czk(kRouteFee)}'), findsWidgets,
      reason: 'the sheet shows the routed distance and the form\'s fee');
  await _tap(t, find.text(_cs('v2AddrConfirm')));
  expect(find.byType(TextField), findsNothing, reason: 'sheet closed');
}

/// The booking form's own state must not move while the calculator is used.
void _expectFormUntouched(ProviderContainer c) {
  final d = c.read(bookingDraftProvider);
  expect([d.motoId, d.pickupMethod, d.returnMethod, d.pickupCity, d.returnCity], [null, 'store', 'store', null, null]);
  expect([
    c.read(pickupDelivFeeProvider),
    c.read(pickupDistKmProvider),
    c.read(returnDelivFeeProvider),
    c.read(returnDistKmProvider),
  ], [0, 0, 0, 0]);
  expect(c.read(bookingMotoProvider), isNull);
}

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
  final pickupLabel = BookingPriceV2.deliveryLabel(_cs('deliveryFee'), kRouteFee);
  final returnLabel = BookingPriceV2.deliveryLabel(_cs('returnFee'), kRouteFee);

  testWidgets('eligible bike: the form\'s rows; delivery + address → fee line, total, CTA price', (t) => deliveryNet(() async {
        final c = await _pumpCalc(t, CalcState(motoId: 'm-bmw', start: ws, end: we));
        final base = quoteFor(kBmw, ws, we, loyalty: kLoyalty3);
        // Before choosing: both sides at the branch, both delivery options offered.
        expect(find.byType(BkOptionRow), findsNWidgets(4));
        expect(find.byType(BookingLockedOptionTile), findsNothing);
        expect(t.widgetList<BkOptionRow>(_opt(_cs('atBranch'))).map((w) => w.selected), [true, true]);
        expect(t.widget<BkOptionRow>(_opt(_cs('v2BkDeliveryTo'))).sub, _cs('deliveryPriceInfo'));
        expect(find.text(_cs('cdHandoverInfo')), findsOneWidget);
        expect(_price(t, base.total), isTrue);
        expect(c.read(calcStateProvider).handover, isNull);

        // Delivery chosen, no address yet: as the form — no fee, a hint.
        await _tap(t, _opt(_cs('v2BkDeliveryTo')));
        expect(c.read(calcStateProvider).handover!.choice.draft.pickupMethod, 'delivery');
        expect(_in(CalcTotalV2, find.text(_cs('efoNoAddrCtx'))), findsOneWidget);
        expect(_price(t, base.total), isTrue);
        expect(_in(CalcReceiptV2, find.textContaining(_cs('deliveryFee'))), findsNothing);

        await _enterProfileAddress(t);
        final h = c.read(calcStateProvider).handover!;
        expect([h.choice.draft.pickupCity, h.choice.draft.pickupAddress, h.choice.pickupFee, h.choice.pickupKm, h.branchId],
            ['Jihlava', 'Masarykovo náměstí 1', kRouteFee, kRouteKm, 'b-mezna']);
        expect([h.choice.draft.returnMethod, h.choice.returnFee], ['store', 0]);
        // Step: the address with its "~km · fee" line; receipt: the form's label.
        expect(find.text('Masarykovo náměstí 1, Jihlava'), findsOneWidget);
        expect(_in(CalcStepHandoverV2, find.text('~32 km · ${Money.czk(kRouteFee)}')), findsOneWidget);
        expect(pickupLabel, 'Přistavení (32 km × 40 + 1 000)');
        expect(bkNbAmounts(pickupLabel), contains('1\u00A0000'), reason: 'the amount never splits across lines');
        expect(_in(CalcReceiptV2, find.text(bkNbAmounts(pickupLabel))), findsOneWidget);
        expect(_in(CalcReceiptV2, find.text('+${Money.czk(kRouteFee)}')), findsOneWidget);
        final q = quoteFor(kBmw, ws, we, loyalty: kLoyalty3, pickupDeliveryFee: kRouteFee);
        expect(q.total, base.total + kRouteFee, reason: 'the rank discount does not apply to delivery');
        expect(_price(t, q.total), isTrue);
        expect(_in(CalcReceiptV2, find.text(Money.czk(q.total))), findsOneWidget);
        expect(find.text(_cs('efoNoAddrCtx')), findsNothing);
        // The average per day stays the rental's.
        expect(
            _in(CalcTotalV2,
                find.text(AppTranslations.of('cs').trArgs('v2AvgPerDay', {'amount': Money.czk((base.total / 3).roundToDouble())}))),
            findsOneWidget);
        _expectFormUntouched(c);
        await _unmount(t);
      }));

  testWidgets('return side: takes the pickup address with its fee; then its own choice back at the branch', (t) => deliveryNet(() async {
        final c = await _pumpCalc(t, CalcState(motoId: 'm-bmw', start: ws, end: we));
        final base = quoteFor(kBmw, ws, we, loyalty: kLoyalty3);
        await _tap(t, _opt(_cs('v2BkDeliveryTo')));
        await _enterProfileAddress(t);
        // "Nothing typed twice": the return side takes the address and the fee.
        await _tap(t, _opt(_cs('v2BkReturnFrom')));
        var h = c.read(calcStateProvider).handover!.choice;
        expect([h.draft.returnMethod, h.draft.returnCity, h.returnFee, h.returnKm], ['delivery', 'Jihlava', kRouteFee, kRouteKm]);
        expect(find.text(_cs('bkAddrSamePickup')), findsOneWidget);
        expect(_in(CalcReceiptV2, find.text(bkNbAmounts(pickupLabel))), findsOneWidget);
        expect(_in(CalcReceiptV2, find.text(bkNbAmounts(returnLabel))), findsOneWidget);
        expect(_price(t, base.total + 2 * kRouteFee), isTrue);
        // Pickup back at the branch: only the collection is charged.
        await _tap(t, _opt(_cs('atBranch')).first);
        h = c.read(calcStateProvider).handover!.choice;
        expect([h.draft.pickupMethod, h.pickupDue, h.returnDue], ['store', 0, kRouteFee]);
        expect(_in(CalcReceiptV2, find.text(bkNbAmounts(pickupLabel))), findsNothing);
        expect(_in(CalcReceiptV2, find.text(bkNbAmounts(returnLabel))), findsOneWidget);
        expect(_price(t, base.total + kRouteFee), isTrue);
        _expectFormUntouched(c);
        await _unmount(t);
      }));

  testWidgets('collection only (no delivery): its own address and fee', (t) => deliveryNet(() async {
        final c = await _pumpCalc(t, CalcState(motoId: 'm-bmw', start: ws, end: we));
        final base = quoteFor(kBmw, ws, we, loyalty: kLoyalty3);
        await _tap(t, _opt(_cs('v2BkReturnFrom')));
        expect(_in(CalcTotalV2, find.text(_cs('efoNoRetAddrCtx'))), findsOneWidget);
        await _enterProfileAddress(t);
        final h = c.read(calcStateProvider).handover!.choice;
        expect([h.draft.pickupMethod, h.draft.returnMethod, h.draft.returnCity, h.pickupDue, h.returnDue],
            ['store', 'delivery', 'Jihlava', 0, kRouteFee]);
        expect(_in(CalcReceiptV2, find.text(bkNbAmounts(returnLabel))), findsOneWidget);
        expect(_price(t, base.total + kRouteFee), isTrue);
        await _unmount(t);
      }));

  testWidgets('self-service bike: the form\'s locked tiles with its explanation; nothing to choose, no fee', (t) async {
    final c = await _pumpCalc(t, CalcState(motoId: 'm-husq', start: ws, end: we));
    expect(find.byType(BookingLockedOptionTile), findsNWidgets(2));
    expect(find.byType(BkOptionRow), findsNWidgets(2), reason: 'only the two branch rows');
    expect(t.widgetList<BkOptionRow>(find.byType(BkOptionRow)).map((w) => [w.title, w.sub, w.selected]),
        everyElement([_cs('atBranch'), 'Velké Němčice', true]));
    expect(find.text(_cs('ssNoDeliveryShort')), findsNWidgets(2));
    expect(find.text(_cs('v2BkDeliveryTo')), findsOneWidget);
    expect(find.text(_cs('v2BkReturnFrom')), findsOneWidget);
    expect(find.text(_cs('ssNoDeliveryInfo')), findsNothing);
    await _tap(t, find.text(_cs('v2BkDeliveryTo')));
    expect(find.text(_cs('ssNoDeliveryInfo')), findsOneWidget, reason: 'tap = the explanation, as in the form');
    expect(c.read(calcStateProvider).handover, isNull);
    expect(_price(t, quoteFor(kHusq, ws, we, loyalty: kLoyalty3).total), isTrue);
    await _unmount(t);
  });

  testWidgets('flag self_service_delivery ON: the self-service bike offers delivery like the form', (t) async {
    await _pumpCalc(t, CalcState(motoId: 'm-husq', start: ws, end: we), selfServiceDelivery: true);
    expect(find.byType(BookingLockedOptionTile), findsNothing);
    expect(find.byType(BkOptionRow), findsNWidgets(4));
    await _unmount(t);
  });

  testWidgets('bike switched to a self-service one after an address: delivery off, fee gone, lock shown', (t) async {
    final own = CalcHandover(choice: jihlavaHandover(ret: true), branchId: kBmw.branchId);
    final c = await _pumpCalc(t, CalcState(motoId: 'm-bmw', start: ws, end: we, handover: own));
    expect(_price(t, quoteFor(kBmw, ws, we, loyalty: kLoyalty3).total + 2 * kRouteFee), isTrue);
    expect(_in(CalcReceiptV2, find.text(bkNbAmounts(pickupLabel))), findsOneWidget);

    c.read(calcStateProvider.notifier).setMoto('m-husq');
    await _steps(t, 3);
    expect(c.read(calcStateProvider).handover, isNull, reason: 'another branch: the form drops the handover too');
    expect(find.byType(BookingLockedOptionTile), findsNWidgets(2));
    expect(find.text(_cs('ssNoDeliveryShort')), findsNWidgets(2));
    expect(find.textContaining('Jihlava'), findsNothing);
    expect(_in(CalcReceiptV2, find.textContaining(_cs('deliveryFee'))), findsNothing);
    expect(_price(t, quoteFor(kHusq, ws, we, loyalty: kLoyalty3).total), isTrue);

    // Back to the staffed bike: a new choice is needed (as in the form).
    c.read(calcStateProvider.notifier).setMoto('m-bmw');
    await _steps(t, 3);
    expect(t.widgetList<BkOptionRow>(_opt(_cs('atBranch'))).map((w) => w.selected), [true, true]);
    expect(_price(t, quoteFor(kBmw, ws, we, loyalty: kLoyalty3).total), isTrue);
    await _unmount(t);
  });

  testWidgets('another bike of the same branch keeps the address and fee', (t) async {
    final own = CalcHandover(choice: jihlavaHandover(), branchId: kBmw.branchId);
    final c = await _pumpCalc(t, CalcState(motoId: 'm-bmw', start: ws, end: we, handover: own));
    c.read(calcStateProvider.notifier).setMoto('m-kid');
    await _steps(t, 3);
    expect(c.read(calcStateProvider).handover!.choice.pickupDue, kRouteFee);
    expect(_in(CalcReceiptV2, find.text(bkNbAmounts(pickupLabel))), findsOneWidget);
    expect(_price(t, quoteFor(kKids, ws, we, loyalty: kLoyalty3).total + kRouteFee), isTrue);
    await _unmount(t);
  });

  testWidgets('no bike: hints only; the free-bike list is unchanged', (t) async {
    await _pumpCalc(t, CalcState(start: ws, end: we));
    expect(find.text(_cs('cdHandoverNoMoto')), findsOneWidget);
    expect(find.text(_cs('cdHandoverInfo')), findsOneWidget);
    expect(find.byType(BkOptionRow), findsNothing);
    expect(find.byType(CalcTotalV2), findsNothing);
    await _unmount(t);
  });

  group('lead time (the form\'s own message, information only)', () {
    Future<void> pumpStep(WidgetTester t, DateTime start, HandoverChoice choice) async {
      final st = CalcState(motoId: kBmw.id, start: start, end: start, handover: CalcHandover(choice: choice, branchId: kBmw.branchId));
      await pumpV2(t, Consumer(builder: (ctx, ref, _) {
        return SingleChildScrollView(
            child: CalcStepHandoverV2(moto: kBmw, st: st, view: calcHandoverView(ref, st, kBmw, t0(ctx))));
      }), size: const Size(412, 1400), overrides: catalogOverrides(profile: kProfileJihlava));
      await _steps(t, 2);
    }

    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1);

    testWidgets('delivery with a start inside the 6 h lead time → the warning; the step stays usable', (t) async {
      await pumpStep(t, yesterday, jihlavaHandover());
      expect(find.text(_cs('validationDeliveryLeadTime')), findsOneWidget);
      expect(t.widget<CalcHint>(find.widgetWithText(CalcHint, _cs('validationDeliveryLeadTime'))).warn, isTrue);
      expect(find.byType(BkOptionRow), findsNWidgets(4));
      await _unmount(t);
    });

    testWidgets('no warning far enough ahead, nor for a pickup at the branch', (t) async {
      await pumpStep(t, ws, jihlavaHandover());
      expect(find.text(_cs('validationDeliveryLeadTime')), findsNothing);
      await _unmount(t);
      // Only the pickup side has a lead time (as the form's validator).
      await pumpStep(t, yesterday, jihlavaHandover(pickup: false, ret: true));
      expect(find.text(_cs('validationDeliveryLeadTime')), findsNothing);
      await _unmount(t);
    });
  });

  testWidgets('reduced motion: choosing delivery and entering the address works without animations', (t) => deliveryNet(() async {
        final c = await _pumpCalc(t, CalcState(motoId: 'm-bmw', start: ws, end: we), reducedMotion: true);
        await _tap(t, _opt(_cs('v2BkDeliveryTo')));
        await _enterProfileAddress(t);
        expect(c.read(calcStateProvider).handover!.choice.pickupDue, kRouteFee);
        expect(_in(CalcReceiptV2, find.text(bkNbAmounts(pickupLabel))), findsOneWidget);
        expect(t.takeException(), isNull);
        await _unmount(t);
      }));

  test('fixture sanity: the draft a calculator never touched', () {
    expect([BookingDraft().pickupMethod, BookingDraft().returnMethod], ['store', 'store']);
    expect(kBmw.branchType == 'obslužná' && kHusq.branchType == 'samoobslužná', isTrue);
    expect(<Motorcycle>[kBmw, kKids].every((m) => m.branchId == 'b-mezna'), isTrue);
  });
}

/// Language of the pumped context.
String t0(BuildContext c) => t(c).lang;
