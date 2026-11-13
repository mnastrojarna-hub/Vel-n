import 'dart:async';

// RGO-3: safeguards of partition "order" tested as BEHAVIOUR (not only via
// helpers): G-346 a tap on the highlighted tab inside the booking form keeps
// the form (AppShellV2._onTab); G-350 Home and Motorky headers draw the
// Velín banner in its own colours (BannerData.bg / color passed through);
// G-154 a rental shorter than the bike's minimum is warned in the detail
// dock; G-125 the Home bike list shows no "Volná v termínu" while the list
// for new dates reloads.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/banner_provider.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/chrome/v2_nav_bar.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_detail_screen.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/catalog/v2/catalog_mode.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_dock_v2.dart';
import 'package:motogo_app/features/catalog/v2/moto_card_full_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_header_v2.dart';
import 'package:motogo_app/features/home/v2/home_bike_list_v2.dart';
import 'package:motogo_app/features/home/v2/home_header_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_catalog.dart';
import '../support/fakes_home.dart' hide kMotos;
import '../support/shell_harness.dart';
import '../support/v2_harness.dart';

final _cs = AppTranslations.of('cs');
const _red = Color(0xFFD92D20), _white = Color(0xFFFFFFFF);
const _banner = BannerData(enabled: true, text: 'Dnes zavřeno', bg: _red, color: _white);

Future<void> _pump(WidgetTester t, String initial, List<Override> overrides, {Widget? home}) async {
  t.view.physicalSize = const Size(412, 915) * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final router = GoRouter(initialLocation: initial, routes: [
    GoRoute(path: '/', builder: (_, __) => Scaffold(body: home ?? const SizedBox())),
    GoRoute(path: '/moto/:id', builder: (_, s) => MotoDetailScreen(motoId: s.pathParameters['id']!)),
    GoRoute(path: '/booking', builder: (_, __) => const Text('booking')),
  ]);
  addTearDown(router.dispose);
  await t.pumpWidget(ProviderScope(
    overrides: [
      rankTokensProvider.overrideWithValue(RankTokens.forLevel(3)),
      rankArcPctProvider.overrideWithValue(50),
      ...overrides,
    ],
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
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 2));
}

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

  testWidgets('G-346: on /booking a tap on the highlighted Motorky tab keeps the form', (t) async {
    final router = await pumpShellV2(t, '/', paths: [...kShellTestPaths, '/booking']);
    router.push('/booking');
    await t.pumpAndSettle();
    final motorky = find.descendant(of: find.byType(V2NavBar), matching: find.text(_cs.tr('v2TabBikes')));
    expect(motorky, findsOneWidget);
    await t.tap(motorky);
    await t.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.last.matchedLocation, '/booking');
    expect(find.text('PAGE /booking'), findsOneWidget);
  });

  testWidgets('G-350: Home header strip in the Velín colours', (t) async {
    await _pump(t, '/', [...homeOverrides(), bannerProvider.overrideWithValue(const AsyncData(_banner))],
        home: const SingleChildScrollView(child: HomeHeaderV2()));
    final strip = t.widget<Container>(find.byKey(const ValueKey('mg-top-banner-strip')));
    expect((strip.decoration as BoxDecoration).color, _red);
    expect(t.widgetList<Text>(find.text('Dnes zavřeno')).every((x) => x.style?.color == _white), isTrue);
    await _unmount(t);
  });

  testWidgets('G-350: Motorky header strip in the Velín colours', (t) async {
    await pumpV2(
        t,
        SingleChildScrollView(
            child: MotorkyHeaderV2(mode: CatalogMode.find, onMode: (_) {}, onBack: () {}, onMenu: () {})),
        overrides: [...catalogOverrides(), bannerProvider.overrideWithValue(const AsyncData(_banner))]);
    await t.pump(const Duration(milliseconds: 300));
    final strip = t.widget<Container>(find.byKey(const ValueKey('motorky-banner-strip')));
    expect((strip.decoration as BoxDecoration).color, _red);
    expect(t.widget<Text>(find.text('Dnes zavřeno')).style?.color, _white);
  });

  testWidgets('G-154: range shorter than the bike minimum → dock warning (validationMinDays)', (t) async {
    final minMoto = Motorcycle(
      id: 'm-min',
      model: kBmw.model,
      category: kBmw.category,
      licenseGroups: kBmw.licenseGroups,
      status: 'active',
      branchId: kBmw.branchId,
      branchName: kBmw.branchName,
      branchCity: kBmw.branchCity,
      branchType: kBmw.branchType,
      branchIsOpen: true,
      minRentalDays: 30,
      prices: kBmw.prices,
      availableToday: true,
    );
    await _pump(t, '/moto/m-min', catalogOverrides(motos: [...kMotos, minMoto], filter: dated));
    final warn = find.descendant(of: find.byType(DetailDockV2), matching: find.byKey(const ValueKey('detail-dock-warning')));
    expect(warn, findsOneWidget);
    final text = _cs.tr('validationMinDays').replaceAll('{n}', '30');
    expect(find.descendant(of: warn, matching: find.textContaining(text.substring(0, 20))), findsOneWidget);
    await _unmount(t);
  });

  testWidgets('G-125: Home bike list — no "Volná v termínu" while the list for new dates reloads', (t) async {
    final s2 = DateTime(ws.year, ws.month, ws.day + 7), e2 = DateTime(we.year, we.month, we.day + 7);
    await _pump(t, '/', [
      ...homeOverrides(),
      ...catalogOverrides(filter: dated),
      filteredMotorcyclesProvider.overrideWith((ref) {
        final f = ref.watch(catalogFilterProvider);
        return f.startDate == s2 ? Completer<List<Motorcycle>>().future : Future.value(kMotos);
      }),
    ], home: const CustomScrollView(slivers: [HomeBikeListV2()]));
    final free = _cs.tr('v2CatFreeInRange');
    expect(find.byType(MotoCardFullV2), findsWidgets);
    expect(find.text(free), findsWidgets);
    final c = ProviderScope.containerOf(t.element(find.byType(HomeBikeListV2)));
    c.read(catalogFilterProvider.notifier).state = CatalogFilter(startDate: s2, endDate: e2);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text(free), findsNothing);
    await _unmount(t);
  });
}
