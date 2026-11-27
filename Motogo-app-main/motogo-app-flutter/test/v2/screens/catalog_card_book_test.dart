// Motorky card taps (owner 2026-11-07 "jen upgrade vzhledu" + 2026-11-27
// "Rezervovat vedle Detail"): "Detail" and the photo open the detail with
// the shown sibling ids, as before; "Rezervovat" is the detail's own
// reserve entry pressed from the list — with usable dates the booking form
// (`startBookingFromSelection`), without them that bike's detail at its
// date step.
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
import 'package:motogo_app/core/v2/widgets/mg_buttons.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/core/feature_flags.dart';
import 'package:motogo_app/features/booking/booking_provider.dart';
import 'package:motogo_app/features/booking/my_vouchers.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/catalog/v2/bike_card_reserve_v2.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_dates_carry_v2.dart';
import 'package:motogo_app/features/catalog/v2/moto_card_full_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';
import 'package:motogo_app/features/reservations/reservation_provider.dart';
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

/// The cards sit under the inline dates + filter (old order): drag the list.
Future<void> _toCard(WidgetTester t) async {
  for (var i = 0; i < 12 && find.byType(MotoCardFullV2).evaluate().isEmpty; i++) {
    await t.drag(find.byType(CustomScrollView).first, const Offset(0, -300));
    await t.pump(const Duration(milliseconds: 300));
  }
  await t.ensureVisible(find.byType(MotoCardFullV2).first);
  await t.pump(const Duration(milliseconds: 300));
}

Future<ProviderContainer> _pump(WidgetTester t, List<Override> overrides) async {
  t.view.physicalSize = const Size(412, 915) * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final router = GoRouter(initialLocation: '/search', routes: [
    GoRoute(path: '/search', builder: (_, __) => const MotorkyScreenV2()),
    GoRoute(path: '/moto/:id', builder: (_, s) => Text('detail:${s.pathParameters['id']}')),
    GoRoute(path: '/booking', builder: (_, __) => const Scaffold(body: BookingDebugWrapper())),
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
        enabled: true,
        child: MediaQuery(data: MediaQuery.of(ctx).copyWith(disableAnimations: true), child: child!),
      ),
    ),
  ));
  await _settle(t);
  return c;
}

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
}

Future<void> _unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 2));
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
  final cs = AppTranslations.of('cs');

  Finder detailBtn() =>
      find.descendant(of: find.byType(MotoCardFullV2).first, matching: find.byKey(const ValueKey('bike-card-detail')));
  Finder reserveBtn() =>
      find.descendant(of: find.byType(MotoCardFullV2).first, matching: find.byKey(const ValueKey('bike-card-reserve')));

  Future<void> tapBtn(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pump();
    await t.tap(f);
    await _settle(t);
  }

  test('the detail\'s rule: REZERVOVAT only with a start day that is not busy', () {
    final d = DateTime(2030, 6, 1);
    expect(detailCanReserve(null, false), isFalse);
    expect(detailCanReserve(d, true), isFalse);
    expect(detailCanReserve(d, false), isTrue);
  });

  testWidgets('the card has "Detail" (secondary) and "Rezervovat" (the rank CTA) side by side', (t) async {
    await _pump(t, catalogOverrides(filter: dated, filtered: [kBmw, kHusq], profile: _profile));
    await _toCard(t);
    expect(t.widget(detailBtn()), isA<MgBtnGhostDark>());
    expect(t.widget<MgBtnGhostDark>(detailBtn()).label, cs.tr('motoCardDetail'));
    final cta = find.descendant(of: reserveBtn(), matching: find.byType(MgCta));
    expect(t.widget<MgCta>(cta).label, cs.tr('v2CatCtaBook'));
    expect(find.descendant(of: find.byType(MotoCardFullV2).first, matching: find.byType(MgCta)), findsOneWidget);
    final d = t.getRect(detailBtn()), r = t.getRect(reserveBtn());
    expect(d.right, lessThanOrEqualTo(r.left), reason: 'Detail left of Rezervovat');
    expect((d.center.dy - r.center.dy).abs(), lessThan(1), reason: 'one row');
    expect(r.width, greaterThan(d.width), reason: 'Rezervovat is the primary');
    await _unmount(t);
  });

  testWidgets('dates set: "Detail" → the detail (no booking)', (t) async {
    final c = await _pump(t, catalogOverrides(filter: dated, filtered: [kBmw, kHusq], profile: _profile));
    await _toCard(t);
    await tapBtn(t, detailBtn());
    expect(find.text('detail:m-bmw'), findsOneWidget);
    expect(find.byType(BookingDebugWrapper), findsNothing);
    expect(c.read(bookingDraftProvider).motoId, isNull);
    expect(c.read(filteredMotoIdsProvider), ['m-bmw', 'm-husq']);
    expect(c.read(detailPickDatesRequestProvider), isNull);
    await _unmount(t);
  });

  testWidgets('dates set: "Rezervovat" → the booking form with those dates (the detail\'s entry)', (t) async {
    final c = await _pump(t, catalogOverrides(filter: dated, filtered: [kBmw, kHusq], profile: _profile));
    await _toCard(t);
    await tapBtn(t, reserveBtn());
    expect(find.byType(BookingDebugWrapper), findsOneWidget);
    expect(find.text('detail:m-bmw'), findsNothing);
    // Exactly what `startBookingFromSelection` writes for the detail.
    final d = c.read(bookingDraftProvider);
    expect(d.motoId, 'm-bmw');
    expect(d.startDate, ws);
    expect(d.endDate, we);
    expect(d.helmetSize, 'L');
    expect(d.glovesSize, 'M');
    expect(d.bootsSize, isNull);
    expect(c.read(bookingMotoProvider)?.id, 'm-bmw');
    expect(c.read(detailPickDatesRequestProvider), isNull);
    await _unmount(t);
  });

  testWidgets('dates set but this bike\'s loaded calendar is busy then → its detail at the date step', (t) async {
    final busy = {
      'm-bmw': [BookedDateRange(start: ws, end: we, status: 'reserved')],
    };
    final c = await _pump(
        t, catalogOverrides(filter: dated, filtered: [kBmw, kHusq], profile: _profile, booked: busy));
    // The calendar of this bike is loaded (as under an open detail) and so
    // are the customer's bookings (the shell keeps them).
    final sub = c.listen(bookedDatesProvider('m-bmw'), (_, __) {});
    final own = c.listen(reservationsProvider, (_, __) {});
    addTearDown(sub.close);
    addTearDown(own.close);
    await _settle(t);
    await _toCard(t);
    await tapBtn(t, reserveBtn());
    expect(find.text('detail:m-bmw'), findsOneWidget);
    expect(find.byType(BookingDebugWrapper), findsNothing);
    expect(c.read(bookingDraftProvider).motoId, isNull);
    expect(c.read(detailPickDatesRequestProvider), 'm-bmw');
    await _unmount(t);
  });

  testWidgets('dates set: the photo still opens the detail', (t) async {
    final c = await _pump(t, catalogOverrides(filter: dated, filtered: [kBmw, kHusq]));
    await _toCard(t);
    await t.tapAt(t.getTopLeft(find.byType(MotoCardFullV2).first) + const Offset(206, 140));
    await _settle(t);
    expect(find.text('detail:m-bmw'), findsOneWidget);
    expect(c.read(bookingDraftProvider).motoId, isNull);
    await _unmount(t);
  });

  testWidgets('no dates: "Detail" → detail with the shown sibling ids', (t) async {
    final c = await _pump(t, catalogOverrides(filtered: [kBmw, kHusq, kKids]));
    await _toCard(t);
    await tapBtn(t, detailBtn());
    expect(find.text('detail:m-bmw'), findsOneWidget);
    expect(c.read(filteredMotoIdsProvider), ['m-bmw', 'm-husq', 'm-kid']);
    expect(c.read(bookingDraftProvider).motoId, isNull);
    expect(c.read(detailPickDatesRequestProvider), isNull);
    await _unmount(t);
  });

  testWidgets('no dates: "Rezervovat" → that bike\'s detail, asked to open on its date step', (t) async {
    final c = await _pump(t, catalogOverrides(filtered: [kBmw, kHusq, kKids], profile: _profile));
    await _toCard(t);
    await tapBtn(t, reserveBtn());
    expect(find.text('detail:m-bmw'), findsOneWidget);
    expect(find.byType(BookingDebugWrapper), findsNothing);
    expect(c.read(filteredMotoIdsProvider), ['m-bmw', 'm-husq', 'm-kid'], reason: 'the card\'s own open');
    expect(c.read(bookingDraftProvider).motoId, isNull);
    expect(c.read(detailPickDatesRequestProvider), 'm-bmw');
    await _unmount(t);
  });
}
