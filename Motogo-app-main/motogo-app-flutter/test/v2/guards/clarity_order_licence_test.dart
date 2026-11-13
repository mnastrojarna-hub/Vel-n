// Clarity "order" J3 / J4 / J5 (new look): a licence that does not cover
// the bike is told EARLY — Home funnel warning with a warn icon and the
// form's own fix "Doplnit v profilu" (→ /profile), REZERVOVAT secondary but
// the same tap; the detail's licence chip red with "tvůj ŘP nestačí" even
// before dates, the dock's REZERVOVAT secondary (still enabled); the
// catalog card's chip the same. Lists, filters and targets unchanged.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/icons/mg_icon.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/core/v2/states/mg_state_banner.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/auth/auth_provider.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_detail_screen.dart';
import 'package:motogo_app/features/catalog/moto_model.dart' show BookedDateRange;
import 'package:motogo_app/features/catalog/v2/catalog_price.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_dock_v2.dart';
import 'package:motogo_app/features/catalog/v2/moto_card_full_v2.dart';
import 'package:motogo_app/features/home/v2/home_funnel_v2.dart';
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
    GoRoute(path: '/booking', builder: (_, __) => const Text('booking-page')),
    GoRoute(path: '/profile', builder: (_, __) => const Text('profile-page')),
  ]);
  final c = ProviderContainer(overrides: [
    rankTokensProvider.overrideWithValue(RankTokens.forLevel(3)),
    rankArcPctProvider.overrideWithValue(50),
    ...overrides,
  ]);
  addTearDown(c.dispose);
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: RepaintBoundary(
      key: _shot,
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
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 2));
}

/// Home funnel with [profile] in a nested scope (the shared fakes pin 'A').
Widget _funnel(Map<String, dynamic> profile) => ProviderScope(
      overrides: [profileProvider.overrideWith((ref) async => profile)],
      child: const SingleChildScrollView(child: HomeFunnelV2()),
    );

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
  final notEnough = _cs.tr('coLicNotEnough');
  final funnelOv = [
    ...homeOverrides(funnel: [kBmw]),
    bookedDatesProvider.overrideWith((ref, id) async => const <BookedDateRange>[]),
  ];

  testWidgets('J3: no licence → warn icon, "Doplnit v profilu" → /profile, REZERVOVAT secondary', (t) async {
    await _pump(t, '/', funnelOv, home: _funnel({'full_name': 'Jan Novák', 'license_group': <String>[]}));
    final w = find.byKey(const ValueKey('home-funnel-warning'));
    expect(w, findsOneWidget);
    expect(t.widget<MgStateBanner>(w).icon, MgIcons.warn);
    expect(find.byType(MgCta), findsNothing, reason: 'no looping CTA under a warning');
    expect(find.byKey(const ValueKey('home-funnel-reserve-ghost')), findsOneWidget);
    await t.ensureVisible(w);
    await t.pump();
    await maybeShot(t, _shot, 'clarity_order__home_funnel_licence__cs__412x915');
    final fix = find.descendant(of: w, matching: find.text(_cs.tr('completeProfileBtn')));
    expect(fix, findsOneWidget);
    await t.tap(fix);
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('profile-page'), findsOneWidget);
    await _unmount(t);
  });

  testWidgets('J3: the secondary REZERVOVAT still starts the booking', (t) async {
    await _pump(t, '/', funnelOv, home: _funnel({'full_name': 'Jan Novák', 'license_group': <String>[]}));
    final b = find.byKey(const ValueKey('home-funnel-reserve-ghost'));
    await t.ensureVisible(b);
    await t.pump();
    await t.tap(b);
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('booking-page'), findsOneWidget);
    await _unmount(t);
  });

  testWidgets('J3: licence OK → no warning, looping REZERVOVAT as before', (t) async {
    await _pump(t, '/', funnelOv, home: _funnel({'full_name': 'Jan Novák', 'license_group': ['A']}));
    expect(find.byKey(const ValueKey('home-funnel-warning')), findsNothing);
    expect(t.widget<MgCta>(find.byType(MgCta)).loop, isTrue);
    await _unmount(t);
  });

  testWidgets('J4: A2 profile on the BMW (A) detail, no dates → red chip "tvůj ŘP nestačí"', (t) async {
    await _pump(t, '/moto/m-bmw', catalogOverrides(profile: {'license_group': ['A2']}));
    expect(find.textContaining(notEnough), findsOneWidget);
    await maybeShot(t, _shot, 'clarity_order__detail_licence__cs__412x915');
    await _unmount(t);
  });

  testWidgets('J4: with dates → dock warning, ghost REZERVOVAT still calls onReserve', (t) async {
    await _pump(t, '/moto/m-bmw',
        catalogOverrides(filter: CatalogFilter(startDate: ws, endDate: we), profile: {'license_group': ['A2']}));
    final dock = find.byType(DetailDockV2);
    expect(find.descendant(of: dock, matching: find.byKey(const ValueKey('detail-dock-warning'))), findsOneWidget);
    final ghost = find.descendant(of: dock, matching: find.byKey(const ValueKey('detail-dock-reserve-ghost')));
    expect(ghost, findsOneWidget);
    expect(t.widget<DetailDockV2>(dock).onReserve, isNotNull);
    await maybeShot(t, _shot, 'clarity_order__detail_dock_licence__cs__412x915');
    await t.tap(ghost);
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('booking-page'), findsOneWidget, reason: 'same action as before: the form blocks');
    await _unmount(t);
  });

  testWidgets('J4: A profile → plain chip', (t) async {
    await _pump(t, '/moto/m-bmw', catalogOverrides(profile: {'license_group': ['A']}));
    expect(find.textContaining(notEnough), findsNothing);
    await _unmount(t);
  });

  for (final (name, profile, bad) in [
    ('A2 profile', <String, dynamic>{'license_group': ['A2']}, true),
    ('A profile', <String, dynamic>{'license_group': ['A']}, false),
    ('no profile', null, false),
  ]) {
    testWidgets('J5: catalog card chip, $name', (t) async {
      const price = CatCardPrice(label: 'Cena od', value: '2 727 Kč', unit: '/den', sub: '', grid: '');
      await pumpV2(
        t,
        MotoCardFullV2(moto: kBmw, price: price, availability: null, ctaLabel: 'DETAIL', onOpen: () {}, height: 700),
        overrides: [profileProvider.overrideWith((ref) async => profile)],
        boundaryKey: _shot,
      );
      await t.pump(const Duration(milliseconds: 400));
      expect(t.takeException(), isNull);
      expect(find.textContaining(notEnough), bad ? findsOneWidget : findsNothing);
      expect(find.text('${_cs.tr('motoCardLicensePrefix')}A'), bad ? findsNothing : findsOneWidget);
      if (bad) await maybeShot(t, _shot, 'clarity_order__catalog_card_licence__cs__360x780');
    });
  }

  testWidgets('J5: German 320 px card chip fits', (t) async {
    const price = CatCardPrice(label: 'Ab', value: '2 727 Kč', unit: '/Tag', sub: '', grid: '');
    await pumpV2(
      t,
      MotoCardFullV2(moto: kBmw, price: price, availability: null, ctaLabel: 'DETAIL', onOpen: () {}, height: 600),
      lang: 'de',
      size: const Size(320, 690),
      overrides: [profileProvider.overrideWith((ref) async => {'license_group': ['A2']})],
      boundaryKey: _shot,
    );
    await t.pump(const Duration(milliseconds: 400));
    expect(t.takeException(), isNull);
    expect(find.textContaining(AppTranslations.of('de').tr('coLicNotEnough')), findsOneWidget);
    await maybeShot(t, _shot, 'clarity_order__catalog_card_licence__de__320x690');
  });
}
