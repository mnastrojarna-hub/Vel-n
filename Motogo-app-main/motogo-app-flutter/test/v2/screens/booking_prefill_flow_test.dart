// Owner 2026-10-22 "nikdy nic vyplňovat dvakrát" — the real screens:
// calculator / detail → booking form arrive with the bike + dates filled
// and those sections folded ("Změnit"); going back and REZERVOVAT again
// keeps everything already filled; a date changed in the form follows back
// to the detail; flag OFF keeps the old fresh draft.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/booking_form_widget.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/core/feature_flags.dart';
import 'package:motogo_app/features/booking/booking_entry.dart';
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/booking/booking_provider.dart';
import 'package:motogo_app/features/booking/my_vouchers.dart';
import 'package:motogo_app/features/booking/v2/booking_carry_v2.dart' show bookingDraftOwnerProvider;
import 'package:motogo_app/features/booking/v2/booking_date_v2.dart';
import 'package:motogo_app/features/booking/v2/booking_recap_v2.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_detail_page.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_state.dart';
import 'package:motogo_app/features/catalog/v2/catalog_mode.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';
import 'package:motogo_app/features/catalog/widgets/availability_calendar.dart';
import 'package:motogo_app/features/home/v2/funnel_provider.dart';
import 'package:motogo_app/features/payment/payment_provider.dart' show lastConfirmedBookingProvider;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_booking.dart';
import '../support/fakes_catalog.dart' show catalogOverrides;
import '../support/v2_harness.dart';

const _profile = {
  ...kProfileOk,
  'gear_sizes': {
    'rider': {'helmet': 'L', 'gloves': 'M', 'jacket': 'L', 'pants': 'M'},
  },
};

Future<(GoRouter, ProviderContainer)> _pump(WidgetTester t, String initial, List<Override> overrides, {bool v2 = true}) async {
  t.view.physicalSize = const Size(412, 915) * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final router = GoRouter(initialLocation: initial, routes: [
    GoRoute(path: '/search', builder: (_, __) => const MotorkyScreenV2()),
    GoRoute(path: '/moto/:id', builder: (_, s) => MotoDetailPage(motoId: s.pathParameters['id']!, showBackButton: true)),
    GoRoute(path: '/booking', builder: (_, __) => const Scaffold(body: BookingDebugWrapper())),
    GoRoute(path: '/payment', builder: (_, __) => const Text('PAYMENT')),
  ]);
  final c = ProviderContainer(overrides: [
    rankTokensProvider.overrideWithValue(RankTokens.forLevel(3)),
    rankArcPctProvider.overrideWithValue(50),
    trailerAvailabilityProvider.overrideWith((ref, r) async => const TrailerAvailability(1, 'tr-1')),
    selfServiceDeliveryEnabledProvider.overrideWith((ref) async => false),
    myVouchersProvider.overrideWith((ref) async => const []),
    ...overrides,
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
  // The old detail has looping animations (never settles) → fixed frames.
  if (v2) {
    await _settle(t);
  } else {
    await t.pump();
    await t.pump(const Duration(milliseconds: 800));
  }
  return (router, c);
}

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
}

Future<void> _tapCta(WidgetTester t) async {
  final cta = find.byType(MgCta).last;
  await t.ensureVisible(cta);
  await t.pump();
  await t.tap(cta);
  await _settle(t);
}

Future<void> _back(WidgetTester t, GoRouter r) async {
  r.pop();
  await _settle(t);
}

/// Leaves the detail (disposed) and opens it again with `go`.
Future<void> _freshDetail(WidgetTester t, GoRouter r) async {
  r.go('/payment');
  await _settle(t);
  expect(find.byType(MotoDetailPage), findsNothing);
  r.go('/moto/m-bmw');
  await _settle(t);
}

Future<void> _unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 2));
}

/// What the customer filled in the form (time, place, note, code, consents).
BookingDraft _fill(BookingDraft d) => d.copyWith(
      pickupTime: () => '12:00',
      pickupMethod: 'delivery',
      pickupCity: () => 'Jihlava',
      pickupAddress: () => 'Masarykovo náměstí 1',
      notes: () => 'Přijedu vlakem',
      discounts: [AppliedDiscount(code: 'JARO10', type: DiscountType.percent, value: 10)],
      consentVop: true,
      consentGdpr: true,
    );

void _expectKept(BookingDraft d) {
  expect([d.pickupTime, d.pickupMethod, d.pickupCity, d.notes, d.consentVop, d.consentGdpr],
      ['12:00', 'delivery', 'Jihlava', 'Přijedu vlakem', true, true]);
  expect(d.discounts.map((x) => x.code), ['JARO10']);
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
  final dated = CatalogFilter(startDate: ws, endDate: we);

  testWidgets('calculator → form: bike + dates filled and folded; back + REZERVOVAT keeps the form', (t) async {
    final (r, c) = await _pump(t, '/search', [
      ...catalogOverrides(calc: CalcState(motoId: 'm-bmw', start: ws, end: we), profile: _profile),
      catalogCalcRequestProvider.overrideWith((ref) => true),
    ]);
    await _tapCta(t);
    expect(find.byType(BookingDebugWrapper), findsOneWidget);
    expect(find.descendant(of: find.byType(BookingRecapV2), matching: find.text(kBmw.model)), findsWidgets);
    final dateCard = find.byType(BookingDateCardV2);
    expect(find.descendant(of: dateCard, matching: find.text('Změnit')), findsOneWidget);
    expect(find.byType(AvailabilityCalendar), findsNothing);
    var d = c.read(bookingDraftProvider);
    expect([d.motoId, d.startDate, d.endDate, d.helmetSize], ['m-bmw', ws, we, 'L']);

    c.read(bookingDraftProvider.notifier).state = _fill(d);
    await t.pump();
    await _back(t, r);
    expect(find.byType(MotorkyScreenV2), findsOneWidget);
    await _tapCta(t);
    expect(find.byType(BookingDebugWrapper), findsOneWidget);
    d = c.read(bookingDraftProvider);
    _expectKept(d);
    expect([d.startDate, d.endDate, d.helmetSize], [ws, we, 'L']);
    await _unmount(t);
  });

  // r2: "Změnit" in the form writes the dates back to every place the
  // customer returns to — calculator (same bike), Motorky list and Home
  // funnel (catalog filter) — so REZERVOVAT from any of them keeps them.
  testWidgets('calculator → form → dates changed there → back: calculator, list and funnel follow', (t) async {
    final (r, c) = await _pump(t, '/search', [
      ...catalogOverrides(calc: CalcState(motoId: 'm-bmw', start: ws, end: we), profile: _profile),
      catalogCalcRequestProvider.overrideWith((ref) => true),
    ]);
    await _tapCta(t);
    final s2 = DateTime(ws.year, ws.month, ws.day + 7), e2 = DateTime(we.year, we.month, we.day + 7);
    c.read(bookingDraftProvider.notifier).state = _fill(c.read(bookingDraftProvider));
    t.widget<BookingDateCardV2>(find.byType(BookingDateCardV2)).onRangeSelected(s2, e2);
    await t.pump();
    final st = c.read(calcStateProvider);
    expect([st.motoId, st.start, st.end], ['m-bmw', s2, e2]);
    final f = c.read(catalogFilterProvider);
    expect([f.startDate, f.endDate], [s2, e2]);
    expect(c.read(funnelGivenProvider), FunnelRange(s2, e2));
    await _back(t, r);
    await _tapCta(t);
    final d = c.read(bookingDraftProvider);
    expect([d.startDate, d.endDate], [s2, e2]);
    _expectKept(d);
    await _unmount(t);
  });

  testWidgets('a draft of another (signed-out) account is never carried', (t) async {
    final (_, c) = await _pump(t, '/moto/m-bmw', catalogOverrides(filter: dated, profile: _profile));
    await _tapCta(t);
    c.read(bookingDraftProvider.notifier).state = _fill(c.read(bookingDraftProvider)).copyWith(helmetSize: () => 'XL');
    c.read(pickupDelivFeeProvider.notifier).state = 1500;
    // The draft was seeded by account A; now nobody / account B is signed in.
    c.read(bookingDraftOwnerProvider.notifier).state = 'user-a';
    final el = t.element(find.byType(BookingDebugWrapper).last);
    startBookingFromSelection(el, el as WidgetRef, kBmw, ws, we);
    await _settle(t);
    final d = c.read(bookingDraftProvider);
    expect([d.pickupTime, d.notes, d.consentVop, d.pickupMethod, d.pickupCity], [null, null, false, 'store', null]);
    expect(d.discounts, isEmpty);
    expect(d.helmetSize, 'L', reason: 'B\'s own profile sizes');
    expect(c.read(pickupDelivFeeProvider), 0);
    await _unmount(t);
  });

  testWidgets('detail → form → dates changed there → back: detail shows them, REZERVOVAT keeps all', (t) async {
    final (r, c) = await _pump(t, '/moto/m-bmw', catalogOverrides(filter: dated, profile: _profile));
    await _tapCta(t);
    expect(find.byType(BookingDebugWrapper), findsOneWidget);
    final s2 = DateTime(ws.year, ws.month, ws.day + 7), e2 = DateTime(we.year, we.month, we.day + 7);
    // "Změnit" in the form writes the draft dates (form's _onDatesSelected).
    c.read(bookingDraftProvider.notifier).state =
        _fill(c.read(bookingDraftProvider)).copyWith(startDate: () => s2, endDate: () => e2);
    await t.pump();
    await _back(t, r);
    expect(find.byType(MotoDetailPage), findsOneWidget);
    await _tapCta(t);
    var d = c.read(bookingDraftProvider);
    expect([d.startDate, d.endDate], [s2, e2]);
    _expectKept(d);
    // Reached with `go` (e.g. back from payment): a NEW detail page seeds
    // from the draft too, as long as the catalog filter did not change.
    await _freshDetail(t, r);
    await _tapCta(t);
    d = c.read(bookingDraftProvider);
    expect([d.startDate, d.endDate], [s2, e2]);
    _expectKept(d);
    // A newer catalog choice wins over the draft.
    final s3 = DateTime(ws.year, ws.month, ws.day + 14), e3 = DateTime(we.year, we.month, we.day + 14);
    c.read(catalogFilterProvider.notifier).state = CatalogFilter(startDate: s3, endDate: e3);
    await _freshDetail(t, r);
    await _tapCta(t);
    d = c.read(bookingDraftProvider);
    expect([d.startDate, d.endDate], [s3, e3]);
    _expectKept(d);
    await _unmount(t);
  });

  testWidgets('another bike → time, note and code carried, consents asked again; a confirmed booking starts fresh', (t) async {
    final (_, c) = await _pump(t, '/moto/m-bmw', catalogOverrides(filter: dated, profile: _profile));
    await _tapCta(t);
    c.read(bookingDraftProvider.notifier).state = _fill(c.read(bookingDraftProvider));
    var el = t.element(find.byType(BookingDebugWrapper).last);
    startBookingFromSelection(el, el as WidgetRef, kHusq, ws, we);
    await _settle(t);
    var d = c.read(bookingDraftProvider);
    expect([d.motoId, d.pickupTime, d.notes, d.consentVop, d.pickupMethod], ['m-husq', '12:00', 'Přijedu vlakem', false, 'store']);
    expect(c.read(bookingMotoProvider)?.id, 'm-husq');
    // Paid meanwhile (payment sets lastConfirmedBookingProvider) → the
    // draft belongs to that booking; the next entry starts fresh.
    c.read(lastConfirmedBookingProvider.notifier).state = 'bk-1';
    el = t.element(find.byType(BookingDebugWrapper).last);
    startBookingFromSelection(el, el as WidgetRef, kHusq, ws, we);
    await _settle(t);
    d = c.read(bookingDraftProvider);
    expect([d.pickupTime, d.notes, d.consentVop], [null, null, false]);
    expect(d.discounts, isEmpty);
    await _unmount(t);
  });

  testWidgets('flag OFF: REZERVOVAT still starts a fresh draft (old look unchanged)', (t) async {
    final (_, c) = await _pump(t, '/moto/m-bmw', catalogOverrides(filter: dated, profile: _profile), v2: false);
    c.read(bookingDraftProvider.notifier).state = _fill(BookingDraft(motoId: 'm-bmw', startDate: ws, endDate: we));
    final el = t.element(find.byType(MotoDetailPage));
    startBookingFromSelection(el, el as WidgetRef, kBmw, ws, we);
    await t.pump();
    await t.pump(const Duration(milliseconds: 800));
    final d = c.read(bookingDraftProvider);
    expect([d.pickupTime, d.notes, d.consentVop, d.pickupMethod, d.helmetSize], [null, null, false, 'store', 'L']);
    expect(d.discounts, isEmpty);
    await _unmount(t);
  });
}
