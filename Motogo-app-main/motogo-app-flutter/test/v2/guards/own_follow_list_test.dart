// own_follow F1 (completes owner decision D1, findings SO-1 / W-01): the
// blocked booking form's "Vybrat jinou motorku" opens the bike list at its
// FIRST bike, not on the bike shown last (the one that cannot be booked);
// the dates stay. Opening the list in any other way still returns to the
// bike shown last (`catalogShownMotoProvider`).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/booking_form_widget.dart';
import 'package:motogo_app/core/feature_flags.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/gestures/mg_zone_snap.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/features/booking/booking_entry.dart';
import 'package:motogo_app/features/booking/booking_provider.dart';
import 'package:motogo_app/features/booking/my_vouchers.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_detail_screen.dart';
import 'package:motogo_app/features/catalog/moto_model.dart' show Motorcycle;
import 'package:motogo_app/features/catalog/v2/bike_screen_list_v2.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_dates_carry_v2.dart' show detailShareRange;
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_booking.dart';
import '../support/fakes_catalog.dart' show catalogOverrides, kHusq, kKids, kShotgun;
import '../support/v2_harness.dart';

String _tr(String key) => translations['cs']![key]!;

/// [datedDropsKids]: with dates the Kids bike (the FIRST undated card) is
/// not free → the dated list is shorter and starts with another bike (SF-1,
/// SG-2: the stale undated ids would publish the Kids bike).
Future<(GoRouter, ProviderContainer)> _pump(WidgetTester t, CatalogFilter filter, {bool datedDropsKids = false}) async {
  t.view.physicalSize = const Size(412, 915) * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final router = GoRouter(initialLocation: '/search', routes: [
    GoRoute(path: '/search', builder: (_, __) => const MotorkyScreenV2()),
    GoRoute(path: '/moto/:id', builder: (_, s) => MotoDetailScreen(motoId: s.pathParameters['id']!)),
    GoRoute(path: '/booking', builder: (_, __) => const Scaffold(body: BookingDebugWrapper())),
  ]);
  final c = ProviderContainer(overrides: [
    rankTokensProvider.overrideWithValue(RankTokens.forLevel(3)),
    rankArcPctProvider.overrideWithValue(50),
    trailerAvailabilityProvider.overrideWith((ref, r) async => const TrailerAvailability(1, 'tr-1')),
    selfServiceDeliveryEnabledProvider.overrideWith((ref) async => false),
    myVouchersProvider.overrideWith((ref) async => const []),
    // Licence A2 + B: the BMW (needs A) is blocked on the form; it is the
    // third card here (the list order is the catalogue order).
    ...catalogOverrides(
        motos: [kHusq, kShotgun, kBmw, kKids], filter: filter, profile: {...kProfileOk, 'license_group': ['A2', 'B']}),
    if (datedDropsKids)
      filteredMotorcyclesProvider.overrideWith((ref) async =>
          ref.watch(catalogFilterProvider).startDate == null ? [kKids, kHusq, kShotgun, kBmw] : [kHusq, kShotgun, kBmw]),
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
  return (router, c);
}

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
}

ScrollPosition _page(WidgetTester t) => t
    .state<ScrollableState>(find.descendant(of: find.byType(MotorkyScreenV2), matching: find.byType(Scrollable)).first)
    .position;

MgSnapZone _zone(WidgetTester t) =>
    t.renderObject<RenderMgSnapZone>(find.byType(MgSnapZoneSliver, skipOffstage: false)).zone;

/// Scrolls the list to card [i] and opens its detail from the card (the
/// list's own open: sibling ids + push).
Future<void> _openFromList(WidgetTester t, String id, int i) async {
  _page(t).jumpTo(_zone(t).offsetOf(i));
  await t.pump();
  await t.tap(find.byKey(ValueKey('mc-$id')), warnIfMissed: false);
  await _settle(t);
  expect(find.byType(MotoDetailScreen), findsOneWidget);
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

  testWidgets('"Vybrat jinou motorku": the list starts at its first bike; dates kept; other entries unchanged', (t) async {
    final (r, c) = await _pump(t, CatalogFilter(startDate: ws, endDate: we));
    final ids = t.widget<BikeScreenList>(find.byType(BikeScreenList, skipOffstage: false)).ids;
    final k = ids.indexOf('m-bmw');
    expect(k, greaterThan(0), reason: 'the blocked bike is not the first card of this list');

    // The customer scrolls to the BMW and opens it from its card.
    await _openFromList(t, 'm-bmw', k);
    expect(c.read(catalogShownMotoProvider), 'm-bmw');
    // The detail's REZERVOVAT (`startBookingFromSelection`, same bike + dates).
    final el = t.element(find.byType(MotorkyScreenV2, skipOffstage: false));
    startBookingFromSelection(el, el as WidgetRef, kBmw, ws, we);
    await _settle(t);
    expect(c.read(licenseValidationProvider), isNotNull);

    final btn = find.text(_tr('pdPickOtherMoto'));
    await t.ensureVisible(btn);
    await t.pump();
    await t.tap(btn);
    await _settle(t);
    expect(r.routerDelegate.currentConfiguration.uri.path, '/search');
    expect(find.byType(MotoDetailScreen), findsNothing);
    // At the start of the list: the first card is the first bike, not the BMW.
    expect(c.read(catalogShownMotoProvider), ids.first);
    expect(_page(t).pixels, moreOrLessEquals(_zone(t).offsetOf(0), epsilon: 1));
    expect(t.widget<BikeScreenList>(find.byType(BikeScreenList)).ids, ids, reason: 'order untouched');
    final f = c.read(catalogFilterProvider);
    expect([f.startDate, f.endDate], [ws, we]);
    expect(c.read(bookingDraftProvider).motoId, kBmw.id, reason: 'the draft stays as after Back');

    // Ordinary way: open the BMW from the list and go back → lands on it.
    await _openFromList(t, 'm-bmw', k);
    r.pop();
    await _settle(t);
    expect(find.byType(MotoDetailScreen), findsNothing);
    expect(c.read(catalogShownMotoProvider), 'm-bmw');
    expect(_page(t).pixels, moreOrLessEquals(_zone(t).offsetOf(k), epsilon: 1));

    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('SF-1: dates picked in the detail re-filter the list; the button still lands on its first card', (t) async {
    final (r, c) = await _pump(t, const CatalogFilter(), datedDropsKids: true);
    BikeScreenList list() => t.widget<BikeScreenList>(find.byType(BikeScreenList, skipOffstage: false));
    final undated = list().ids;
    expect(undated, ['m-kid', 'm-husq', 'm-shot', 'm-bmw']);
    await _openFromList(t, 'm-bmw', 3);
    final el = t.element(find.byType(MotorkyScreenV2, skipOffstage: false));
    detailShareRange(el as WidgetRef, ws, we); // dates picked in the detail
    await _settle(t);
    final dated = list().ids;
    expect(dated, ['m-husq', 'm-shot', 'm-bmw'], reason: 'the covered list changed under the detail');
    expect(c.read(filteredMotoIdsProvider), undated, reason: 'the pager ids are the stale undated ones');
    startBookingFromSelection(el, el as WidgetRef, kBmw, ws, we);
    await _settle(t);
    final btn = find.text(_tr('pdPickOtherMoto'));
    await t.ensureVisible(btn);
    await t.pump();
    await t.tap(btn);
    await _settle(t);
    expect(r.routerDelegate.currentConfiguration.uri.path, '/search');
    expect(list().ids, dated, reason: 'order untouched');
    expect(c.read(catalogShownMotoProvider), 'm-husq');
    expect(_page(t).pixels, moreOrLessEquals(_zone(t).offsetOf(0), epsilon: 1));
    final f = c.read(catalogFilterProvider);
    expect([f.startDate, f.endDate], [ws, we]);
    // Ordinary way afterwards: open the BMW (now card 2) and go back → on it.
    await _openFromList(t, 'm-bmw', 2);
    r.pop();
    await _settle(t);
    expect(c.read(catalogShownMotoProvider), 'm-bmw');
    expect(_page(t).pixels, moreOrLessEquals(_zone(t).offsetOf(2), epsilon: 1));
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('SG-1: pager swiped back to the first bike while the list sits on a later card; the button still moves the list', (t) async {
    final (r, c) = await _pump(t, const CatalogFilter(), datedDropsKids: true);
    BikeScreenList list() => t.widget<BikeScreenList>(find.byType(BikeScreenList, skipOffstage: false));
    await _openFromList(t, 'm-bmw', 3);
    final el = t.element(find.byType(MotorkyScreenV2, skipOffstage: false));
    detailShareRange(el as WidgetRef, ws, we); // dates picked in the detail
    await _settle(t);
    final dated = list().ids;
    expect(dated, ['m-husq', 'm-shot', 'm-bmw']);
    // Swipe the pager (stale undated ids) back from the BMW to the Husqvarna.
    for (var i = 0; i < 2; i++) {
      await t.drag(find.byType(PageView).first, const Offset(350, 0));
      await _settle(t);
    }
    expect(c.read(catalogShownMotoProvider), dated.first, reason: 'the first bike of the list shown now is already published');
    final covered = t.state<ScrollableState>(find
        .descendant(of: find.byType(MotorkyScreenV2, skipOffstage: false), matching: find.byType(Scrollable, skipOffstage: false))
        .first);
    expect(covered.position.pixels, greaterThan(_zone(t).offsetOf(0) + 1), reason: 'the list itself still sits on a later card');
    startBookingFromSelection(el, el as WidgetRef, kBmw, ws, we);
    await _settle(t);
    final btn = find.text(_tr('pdPickOtherMoto'));
    await t.ensureVisible(btn);
    await t.pump();
    await t.tap(btn);
    await _settle(t);
    expect(r.routerDelegate.currentConfiguration.uri.path, '/search');
    expect(list().ids, dated, reason: 'order untouched');
    expect(c.read(catalogShownMotoProvider), 'm-husq');
    expect(_page(t).pixels, moreOrLessEquals(_zone(t).offsetOf(0), epsilon: 1));
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  });

  test('catalogShowListStart: the list shown now (sorted); stale ids only while it is not loaded; nothing when there are no ids', () async {
    final shown = Completer<List<Motorcycle>>();
    final c = ProviderContainer(overrides: [filteredMotorcyclesProvider.overrideWith((ref) => shown.future)]);
    addTearDown(c.dispose);
    final read = _Reader(c);
    c.read(catalogShownMotoProvider.notifier).state = 'm-bmw';
    c.read(filteredMotoIdsProvider.notifier).state = const [];
    catalogShowListStart(read); // not loaded, no ids
    expect(c.read(catalogShownMotoProvider), 'm-bmw');
    c.read(filteredMotoIdsProvider.notifier).state = const ['m-shot', 'm-bmw'];
    catalogShowListStart(read); // not loaded → the ids the list wrote
    expect(c.read(catalogShownMotoProvider), 'm-shot');
    shown.complete([kBmw, kHusq]);
    await c.read(filteredMotorcyclesProvider.future);
    c.read(catalogSortProvider.notifier).state = 'power_asc';
    catalogShowListStart(read);
    final sorted = sortMotorcycles([kBmw, kHusq], 'power_asc').map((m) => m.id).toList();
    expect(c.read(filteredMotoIdsProvider), sorted);
    expect(c.read(catalogShownMotoProvider), sorted.first);
  });
}

/// A [WidgetRef] over a bare container (reads only).
class _Reader implements WidgetRef {
  final ProviderContainer c;
  _Reader(this.c);
  @override
  T read<T>(ProviderListenable<T> p) => c.read(p);
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}
