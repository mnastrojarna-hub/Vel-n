// Calculator with delivery (owner 2026-11-27: "co jsem v kalkulačce
// naklikal, se musí přenést do rezervace") — the real screens: REZERVOVAT
// carries the place, address and fee of step ④ into the booking form, whose
// price section shows the same lines and the same total as the calculator's
// receipt; the calculator writes NOTHING of the form's state before that;
// an untouched step keeps the previous behaviour; after the hand-over the
// booking draft is the one source (a change made in the form is what the
// calculator shows and keeps); the form re-validates what it got.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/booking_address_carry.dart';
import 'package:motogo_app/core/booking_form_locked_option.dart';
import 'package:motogo_app/core/booking_form_widget.dart';
import 'package:motogo_app/core/currency.dart';
import 'package:motogo_app/core/feature_flags.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/core/v2/widgets/mg_price.dart';
import 'package:motogo_app/features/booking/booking_entry.dart';
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/booking/booking_provider.dart';
import 'package:motogo_app/features/booking/booking_quote.dart';
import 'package:motogo_app/features/booking/my_vouchers.dart';
import 'package:motogo_app/features/booking/v2/booking_carry_v2.dart';
import 'package:motogo_app/features/booking/v2/booking_v2_parts.dart';
import 'package:motogo_app/features/booking/v2/sections/price_v2.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_receipt_v2.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_state.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_step_handover_v2.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_total_v2.dart';
import 'package:motogo_app/features/catalog/v2/catalog_mode.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';
import 'package:motogo_app/features/payment/payment_provider.dart' show lastConfirmedBookingProvider;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_booking.dart';
import '../support/fakes_calc_delivery.dart';
import '../support/fakes_catalog.dart' show catalogOverrides, kShotgun;
import '../support/v2_harness.dart';

String _cs(String key) => translations['cs']![key]!;

Future<(GoRouter, ProviderContainer)> _pump(WidgetTester t, CalcState calc, {List<Override> more = const [], bool v2 = true}) async {
  t.view.physicalSize = const Size(412, 915) * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final router = GoRouter(initialLocation: '/search', routes: [
    GoRoute(path: '/search', builder: (_, __) => const MotorkyScreenV2()),
    GoRoute(path: '/booking', builder: (_, __) => const Scaffold(body: BookingDebugWrapper())),
    GoRoute(path: '/payment', builder: (_, __) => const Text('PAYMENT')),
  ]);
  final c = ProviderContainer(overrides: [
    rankTokensProvider.overrideWithValue(RankTokens.forLevel(3)),
    rankArcPctProvider.overrideWithValue(50),
    trailerAvailabilityProvider.overrideWith((ref, r) async => const TrailerAvailability(1, 'tr-1')),
    selfServiceDeliveryEnabledProvider.overrideWith((ref) async => false),
    myVouchersProvider.overrideWith((ref) async => const []),
    ...catalogOverrides(calc: calc, profile: kProfileJihlava),
    catalogCalcRequestProvider.overrideWith((ref) => true),
    ...more,
  ]);
  addTearDown(c.dispose);
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp.router(
      routerConfig: router,
      locale: const Locale('cs'),
      supportedLocales: supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: v2TestTheme(),
      builder: (ctx, child) => MgV2Scope(
        enabled: v2,
        child: MediaQuery(data: MediaQuery.of(ctx).copyWith(disableAnimations: true), child: child!),
      ),
    ),
  ));
  await _settle(t);
  return (router, c);
}

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await _settle(t);
}

/// REZERVOVAT of the calculator (total block, or the sticky dock).
Future<void> _book(WidgetTester t) => _tap(t, find.byType(MgCta).last);

Future<void> _unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 2));
}

Finder _in(Type scope, Finder f) => find.descendant(of: find.byType(scope), matching: f);
Finder _opt(String title) => find.byWidgetPredicate((w) => w is BkOptionRow && w.title == title);

List<double> _fees(ProviderContainer c) => [
      c.read(pickupDelivFeeProvider),
      c.read(pickupDistKmProvider),
      c.read(returnDelivFeeProvider),
      c.read(returnDistKmProvider),
    ];

List<Object?> _place(BookingDraft d) => [
      d.pickupMethod, d.pickupCity, d.pickupAddress, d.pickupZip, d.pickupLat, d.pickupLng,
      d.returnMethod, d.returnCity, d.returnAddress, d.returnZip, d.returnLat, d.returnLng,
    ];

/// An unfinished booking the customer left in the form: [moto], delivery to
/// Třebíč for 1 800 Kč (20 km), a note and a time.
List<Override> _inProgress(dynamic moto, DateTime s, DateTime e) => [
      bookingMotoProvider.overrideWith((_) => moto),
      bookingDraftProvider.overrideWith((_) => BookingDraft(
            motoId: moto.id as String,
            startDate: s,
            endDate: e,
            pickupTime: '10:00',
            pickupMethod: 'delivery',
            pickupCity: 'Třebíč',
            pickupAddress: 'Karlovo nám. 2',
            notes: 'Přijedu vlakem',
          )),
      pickupDelivFeeProvider.overrideWith((_) => 1800),
      pickupDistKmProvider.overrideWith((_) => 20),
    ];

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
  CalcState calc(String moto, [HandoverChoice? h, String? branch]) => CalcState(
      motoId: moto, start: ws, end: we, handover: h == null ? null : CalcHandover(choice: h, branchId: branch ?? kBmw.branchId));

  testWidgets('REZERVOVAT carries place, address and fee; the form\'s price section = the calculator\'s receipt', (t) async {
    final own = jihlavaHandover(ret: true);
    final (_, c) = await _pump(t, calc('m-bmw', own));
    final q = quoteFor(kBmw, ws, we, loyalty: kLoyalty3, pickupDeliveryFee: kRouteFee, returnDeliveryFee: kRouteFee);
    // The calculator's receipt and total (the form's label; the receipt
    // only keeps "1 000" on one line with a no-break space).
    for (final label in [pickupLabel, returnLabel]) {
      expect(_in(CalcReceiptV2, find.text(bkNbAmounts(label))), findsOneWidget);
      expect(bkNbAmounts(label).replaceAll('\u00A0', ' '), label);
    }
    expect(_in(CalcReceiptV2, find.text('+${Money.czk(kRouteFee)}')), findsNWidgets(2));
    expect(_in(CalcReceiptV2, find.text(Money.czk(q.total))), findsOneWidget);
    expect(t.widgetList<MgCta>(_in(CalcTotalV2, find.byType(MgCta))).single.price, Money.czk(q.total));
    // Nothing of the form's state was written by showing / pricing it.
    expect(c.read(bookingDraftProvider).motoId, isNull);
    expect(_fees(c), [0, 0, 0, 0]);

    await _book(t);
    expect(find.byType(BookingDebugWrapper), findsOneWidget);
    final d = c.read(bookingDraftProvider);
    expect([d.motoId, d.startDate, d.endDate, d.pickupTime], ['m-bmw', ws, we, null]);
    expect(_place(d), _place(own.draft), reason: 'methods, addresses and coordinates as the calculator held them');
    expect(_fees(c), [kRouteFee, kRouteKm, kRouteFee, kRouteKm]);
    expect(d.helmetSize, 'L', reason: 'the rest of the entry is unchanged (sizes from the profile)');
    // Same input → the same price in the form's own provider and section.
    final bd = c.read(priceBreakdownProvider);
    expect([bd.total, bd.pickupDeliveryFee, bd.returnDeliveryFee, bd.loyaltyDiscount],
        [q.total, kRouteFee, kRouteFee, q.loyaltyDiscount]);
    for (final label in [pickupLabel, returnLabel]) {
      expect(_in(BookingPriceV2, find.text(label)), findsOneWidget, reason: 'the same line as in the receipt');
    }
    expect(_in(BookingPriceV2, find.text('+${Money.czk(kRouteFee)}')), findsNWidgets(2));
    expect(t.widget<MgTotalBox>(_in(BookingPriceV2, find.byType(MgTotalBox))).value, Money.czk(q.total));
    // The form shows the carried choice in its own sections.
    expect(t.widgetList<BkOptionRow>(_opt(_cs('v2BkDeliveryTo'))).single.selected, isTrue);
    expect(t.widgetList<BkOptionRow>(_opt(_cs('v2BkReturnFrom'))).single.selected, isTrue);
    expect(find.text('Masarykovo náměstí 1, Jihlava'), findsNWidgets(2));
    // Handed over: from now on the booking draft holds it.
    expect(c.read(calcStateProvider).handover, isNull);
    await _unmount(t);
  });

  testWidgets('guard: step ④ never writes the form\'s draft or fee providers before REZERVOVAT', (t) => deliveryNet(() async {
        // An unfinished booking of ANOTHER bike (same branch) with its own delivery.
        final (_, c) = await _pump(t, calc('m-bmw'), more: _inProgress(kShotgun, ws, we));
        final before = c.read(bookingDraftProvider);
        // Untouched step: it shows what the form would open with (carried place).
        expect(_in(CalcStepHandoverV2, find.text('Karlovo nám. 2, Třebíč')), findsOneWidget);
        // The customer changes everything in the calculator.
        await _tap(t, _in(CalcStepHandoverV2, _opt(_cs('v2BkReturnFrom'))));
        await _tap(t, _in(CalcStepHandoverV2, _opt(_cs('atBranch')).first));
        await _tap(t, _in(CalcStepHandoverV2, _opt(_cs('v2BkDeliveryTo'))));
        await _tap(t, _in(CalcStepHandoverV2, find.text('Karlovo nám. 2, Třebíč').first));
        await _tap(t, find.text(_cs('bkAddrMine')));
        await _tap(t, find.text(_cs('v2AddrConfirm')));
        final h = c.read(calcStateProvider).handover!.choice;
        expect([h.draft.pickupCity, h.pickupFee, h.draft.returnCity, h.returnFee], ['Jihlava', kRouteFee, 'Třebíč', 1800]);
        // The form's state is byte-for-byte what it was.
        expect(identical(c.read(bookingDraftProvider), before), isTrue);
        expect(c.read(bookingMotoProvider)?.id, kShotgun.id);
        expect(_fees(c), [1800, 20, 0, 0]);

        await _book(t);
        final d = c.read(bookingDraftProvider);
        expect([d.motoId, d.pickupMethod, d.pickupCity, d.returnMethod, d.returnCity],
            ['m-bmw', 'delivery', 'Jihlava', 'delivery', 'Třebíč']);
        expect(_fees(c), [kRouteFee, kRouteKm, 1800, 20]);
        expect([d.pickupTime, d.notes], ['10:00', 'Přijedu vlakem'], reason: 'the existing carry of the other fields');
        await _unmount(t);
      }));

  testWidgets('untouched step: the calculator shows the unfinished booking\'s delivery and REZERVOVAT keeps it', (t) async {
    final (_, c) = await _pump(t, calc('m-bmw'), more: _inProgress(kBmw, ws, we));
    final q = quoteFor(kBmw, ws, we, loyalty: kLoyalty3, pickupDeliveryFee: 1800);
    expect(c.read(calcStateProvider).handover, isNull);
    expect(_in(CalcStepHandoverV2, find.text('Karlovo nám. 2, Třebíč')), findsOneWidget);
    expect(_in(CalcReceiptV2, find.text(bkNbAmounts(BookingPriceV2.deliveryLabel(_cs('deliveryFee'), 1800)))), findsOneWidget);
    expect(t.widgetList<MgCta>(_in(CalcTotalV2, find.byType(MgCta))).single.price, Money.czk(q.total),
        reason: 'never a lower price than the form will show');
    await _book(t);
    final d = c.read(bookingDraftProvider);
    expect([d.pickupMethod, d.pickupCity, d.pickupAddress, d.pickupTime, d.notes],
        ['delivery', 'Třebíč', 'Karlovo nám. 2', '10:00', 'Přijedu vlakem']);
    expect(_fees(c), [1800, 20, 0, 0]);
    expect(c.read(priceBreakdownProvider).pickupDeliveryFee, 1800);
    await _unmount(t);
  });

  testWidgets('an explicit "na pobočce" in the calculator wins over the unfinished booking\'s delivery', (t) async {
    final (_, c) = await _pump(t, calc('m-bmw'), more: _inProgress(kBmw, ws, we));
    await _tap(t, _in(CalcStepHandoverV2, _opt(_cs('atBranch')).first));
    expect(c.read(calcStateProvider).handover!.choice.draft.pickupMethod, 'store');
    expect(c.read(bookingDraftProvider).pickupMethod, 'delivery', reason: 'the form is not written yet');
    expect(t.widgetList<MgCta>(_in(CalcTotalV2, find.byType(MgCta))).single.price,
        Money.czk(quoteFor(kBmw, ws, we, loyalty: kLoyalty3).total));
    await _book(t);
    final d = c.read(bookingDraftProvider);
    expect([d.pickupMethod, d.returnMethod, d.notes], ['store', 'store', 'Přijedu vlakem']);
    expect(c.read(priceBreakdownProvider).pickupDeliveryFee, 0);
    await _unmount(t);
  });

  testWidgets('after the hand-over the form is the source: its change is shown by the calculator and kept', (t) async {
    final (r, c) = await _pump(t, calc('m-bmw', jihlavaHandover()));
    await _book(t);
    expect(c.read(bookingDraftProvider).pickupCity, 'Jihlava');
    // The customer changes the address in the FORM (its sheet: fee, then address).
    c.read(pickupDelivFeeProvider.notifier).state = 5000;
    c.read(pickupDistKmProvider.notifier).state = 100;
    c.read(bookingDraftProvider.notifier).state =
        c.read(bookingDraftProvider).copyWith(pickupCity: () => 'Brno', pickupAddress: () => 'Husova 5');
    await t.pump();
    r.pop();
    await _settle(t);
    expect(find.byType(MotorkyScreenV2), findsOneWidget);
    expect(c.read(calcStateProvider).handover, isNull);
    expect(_in(CalcStepHandoverV2, find.text('Husova 5, Brno')), findsOneWidget);
    expect(find.textContaining('Jihlava'), findsNothing, reason: 'no stale calculator address');
    expect(t.widgetList<MgCta>(_in(CalcTotalV2, find.byType(MgCta))).single.price,
        Money.czk(quoteFor(kBmw, ws, we, loyalty: kLoyalty3, pickupDeliveryFee: 5000).total));
    await _book(t);
    final d = c.read(bookingDraftProvider);
    expect([d.pickupMethod, d.pickupCity, d.pickupAddress], ['delivery', 'Brno', 'Husova 5']);
    expect(_fees(c), [5000, 100, 0, 0]);
    await _unmount(t);
  });

  testWidgets('the form re-validates: a carried delivery for a self-service bike falls back to the branch', (t) async {
    final (_, c) = await _pump(t, calc('m-husq'));
    final el = t.element(find.byType(MotorkyScreenV2));
    // Not reachable from the calculator (it drops such a choice itself) —
    // the entry must be safe on its own.
    startBookingFromSelection(el, el as WidgetRef, kHusq, ws, we, handover: jihlavaHandover(ret: true));
    await _settle(t);
    expect(find.byType(BookingDebugWrapper), findsOneWidget);
    final d = c.read(bookingDraftProvider);
    expect([d.motoId, d.pickupMethod, d.returnMethod], ['m-husq', 'store', 'store']);
    final bd = c.read(priceBreakdownProvider);
    expect([bd.pickupDeliveryFee, bd.returnDeliveryFee, bd.total],
        [0, 0, quoteFor(kHusq, ws, we, loyalty: kLoyalty3).total]);
    expect(find.byType(BookingLockedOptionTile), findsNWidgets(2));
    await _unmount(t);
  });

  testWidgets('entry without a handover = before; old look ignores a handover (fresh draft)', (t) async {
    final (_, c) = await _pump(t, calc('m-bmw'), v2: false);
    final el = t.element(find.byType(MotorkyScreenV2));
    startBookingFromSelection(el, el as WidgetRef, kBmw, ws, we, handover: jihlavaHandover());
    await t.pump();
    await t.pump(const Duration(milliseconds: 800));
    final d = c.read(bookingDraftProvider);
    expect([d.motoId, d.pickupMethod, d.pickupCity, d.helmetSize], ['m-bmw', 'store', null, 'L']);
    expect(_fees(c), [0, 0, 0, 0]);
    await _unmount(t);
  });

  group('bookingEntryHandover (what the form would open with)', () {
    ProviderContainer box(List<Override> o) {
      final c = ProviderContainer(overrides: o);
      addTearDown(c.dispose);
      return c;
    }

    test('nothing unfinished → both sides at the branch, no fee', () {
      final h = bookingEntryHandover(box(const []).read, kBmw);
      expect(h, HandoverChoice());
    });

    test('same bike / another bike of the same branch → the unfinished place with its fee', () {
      final c = box(_inProgress(kBmw, ws, we));
      for (final m in [kBmw, kShotgun]) {
        final h = bookingEntryHandover(c.read, m);
        expect([h.draft.pickupMethod, h.draft.pickupCity, h.pickupFee, h.pickupKm, h.pickupDue],
            ['delivery', 'Třebíč', 1800, 20, 1800], reason: m.model);
        expect(h.draft.notes, isNull, reason: 'place only');
      }
      expect(c.read(bookingEntryHandoverProvider(kBmw)), bookingEntryHandover(c.read, kBmw));
    });

    test('another branch, a paid booking meanwhile or another account → nothing carried', () {
      expect(bookingEntryHandover(box(_inProgress(kBmw, ws, we)).read, kHusq), HandoverChoice());
      final paid = box([..._inProgress(kBmw, ws, we), lastConfirmedBookingProvider.overrideWith((_) => 'bk-1')]);
      expect(bookingEntryHandover(paid.read, kBmw), HandoverChoice());
      final other = box([..._inProgress(kBmw, ws, we), bookingDraftOwnerProvider.overrideWith((_) => 'user-a')]);
      expect(bookingEntryHandover(other.read, kBmw), HandoverChoice());
    });
  });
}
