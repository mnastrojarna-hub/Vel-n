import 'dart:async';

// Safeguards G-152 / G-153 / G-154 / G-102 / G-125 / G-145 (new look): the range
// problem of a bike (licence does not cover it, own overlapping booking,
// min / max days) is red and is also shown in the bike detail's sticky dock
// without scrolling, while REZERVOVAT stays enabled as in the old look (the
// booking form blocks); the Home funnel shows the same warning above its
// REZERVOVAT; no "Volná v termínu" pill while the list reloads for new
// dates; a server error on the detail offers "Zavolat MotoGo".
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/core/v2/states/mg_state_banner.dart';
import 'package:motogo_app/core/v2/states/mg_tone.dart';
import 'package:motogo_app/core/v2/widgets/mg_buttons.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_detail_screen.dart';
import 'package:motogo_app/features/catalog/moto_model.dart' show BookedDateRange, Motorcycle;
import 'package:motogo_app/features/catalog/v2/detail/detail_dock_v2.dart';
import 'package:motogo_app/features/catalog/v2/moto_card_full_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';
import 'package:motogo_app/features/catalog/widgets/validation_banner.dart';
import 'package:motogo_app/features/home/v2/funnel_provider.dart';
import 'package:motogo_app/features/home/v2/home_funnel_v2.dart';
import 'package:motogo_app/features/reservations/reservation_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_catalog.dart';
import '../support/fakes_home.dart' hide kMotos;
import '../support/v2_harness.dart';

final _cs = AppTranslations.of('cs');
final _shot = GlobalKey();

Future<void> _pump(WidgetTester t, String initial, List<Override> overrides, {Widget? home}) async {
  t.view.physicalSize = const Size(412, 915) * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final router = GoRouter(initialLocation: initial, routes: [
    GoRoute(path: '/', builder: (_, __) => Scaffold(body: home ?? const SizedBox())),
    GoRoute(path: '/moto/:id', builder: (_, s) => MotoDetailScreen(motoId: s.pathParameters['id']!)),
    GoRoute(path: '/booking', builder: (_, __) => const Text('booking')),
    GoRoute(path: '/search', builder: (_, __) => const MotorkyScreenV2()),
  ]);
  final c = ProviderContainer(overrides: [
    rankTokensProvider.overrideWithValue(RankTokens.forLevel(3)),
    rankArcPctProvider.overrideWithValue(50),
    ...overrides,
  ]);
  addTearDown(c.dispose);
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: RepaintBoundary(key: _shot, child: MaterialApp.router(
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
    )),
  ));
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 2));
}

Reservation _own(DateTime s, DateTime e) => Reservation.fromJson({
      'id': 'own-1',
      'moto_id': 'm-shot',
      'status': 'reserved',
      'payment_status': 'paid',
      'booking_source': 'app',
      'start_date': s.toIso8601String(),
      'end_date': e.toIso8601String(),
      'total_price': 0,
    });

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerCatalogStrings();
    registerHomeStrings();
    mockPathProvider();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MgMotion.resetSession();
  });
  final (ws, we) = futureWeekend();
  final dated = CatalogFilter(startDate: ws, endDate: we);
  final dock = find.byType(DetailDockV2);

  Future<void> expectDockWarning(WidgetTester t) async {
    final warn = find.descendant(of: dock, matching: find.byKey(const ValueKey('detail-dock-warning')));
    expect(warn, findsOneWidget, reason: 'warning visible in the sticky dock');
    final banner = t.widget<MgStateBanner>(
        find.descendant(of: find.byType(ValidationBanner), matching: find.byType(MgStateBanner)));
    expect(banner.tone, MgTone.err, reason: 'red, as the old red box');
    expect(find.descendant(of: warn, matching: find.text(banner.title)), findsOneWidget);
    // J4: with a warning REZERVOVAT is the secondary (ghost) button — still
    // enabled as in the old look (the form blocks), no looping CTA.
    expect(find.descendant(of: dock, matching: find.byType(MgCta)), findsNothing);
    final cta = t.widget<MgBtnGhostDark>(find.descendant(of: dock, matching: find.byType(MgBtnGhostDark)));
    expect(cta.onTap, isNotNull, reason: 'CTA stays enabled as in the old look (the form blocks)');
  }

  testWidgets('G-152: licence does not cover the bike → red banner + dock warning', (t) async {
    await _pump(t, '/moto/m-bmw', catalogOverrides(filter: dated, profile: {'license_group': ['B']}));
    await expectDockWarning(t);
    await maybeShot(t, _shot, 'guards__detail_dock_licence__cs__412x915');
    await _unmount(t);
  });

  testWidgets('G-153: own overlapping booking → dock warning', (t) async {
    await _pump(t, '/moto/m-bmw', catalogOverrides(filter: dated, reservations: [_own(ws, we)]));
    await expectDockWarning(t);
    await _unmount(t);
  });

  testWidgets('no problem → no dock warning, the CTA loops', (t) async {
    await _pump(t, '/moto/m-bmw', catalogOverrides(filter: dated));
    expect(find.byKey(const ValueKey('detail-dock-warning')), findsNothing);
    expect(t.widget<MgCta>(find.descendant(of: dock, matching: find.byType(MgCta))).loop, isTrue);
    await _unmount(t);
  });

  testWidgets('G-102: Home funnel shows the overlap warning above REZERVOVAT', (t) async {
    final r = funnelPresets(DateTime.now()).$1;
    await _pump(t, '/', [
      ...homeOverrides(funnel: kMotos.take(2).toList(), reservations: [_own(r.start, r.end)]),
      bookedDatesProvider.overrideWith((ref, id) async => const <BookedDateRange>[]),
      // v5.0.1: nothing is preselected — the customer gave these dates.
      funnelGivenProvider.overrideWith((ref) => r),
    ], home: const SingleChildScrollView(child: HomeFunnelV2()));
    final w = find.byKey(const ValueKey('home-funnel-warning'));
    expect(w, findsOneWidget);
    expect(t.widget<MgStateBanner>(w).tone, MgTone.err);
    await t.ensureVisible(w);
    await t.pump();
    await maybeShot(t, _shot, 'guards__home_funnel_warning__cs__412x915');
    await _unmount(t);
  });

  testWidgets('G-125: no "Volná v termínu" while the list for new dates reloads', (t) async {
    final s2 = DateTime(ws.year, ws.month, ws.day + 7), e2 = DateTime(we.year, we.month, we.day + 7);
    final ov = catalogOverrides(filter: dated);
    await _pump(t, '/search', [
      ...ov,
      filteredMotorcyclesProvider.overrideWith((ref) {
        final f = ref.watch(catalogFilterProvider);
        return f.startDate == s2 ? Completer<List<Motorcycle>>().future : Future.value(kMotos);
      }),
    ]);
    for (var i = 0; i < 12 && find.byType(MotoCardFullV2).evaluate().isEmpty; i++) {
      await t.drag(find.byType(CustomScrollView).first, const Offset(0, -300));
      await t.pump(const Duration(milliseconds: 300));
    }
    final free = _cs.tr('v2CatFreeInRange');
    expect(find.text(free), findsWidgets);
    final c = ProviderScope.containerOf(t.element(find.byType(MotorkyScreenV2)));
    c.read(catalogFilterProvider.notifier).state = CatalogFilter(startDate: s2, endDate: e2);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text(free), findsNothing);
    await _unmount(t);
  });

  testWidgets('G-145: server error on the detail → "Zavolat MotoGo" button', (t) async {
    await _pump(t, '/moto/m-bmw', catalogOverrides(motosError: Exception('boom 500 server')));
    expect(find.text(_cs.tr('eoCall')), findsOneWidget);
    await _unmount(t);
  });
}
