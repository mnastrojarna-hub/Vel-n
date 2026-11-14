// Owner 2026-10-22 "nikdy nic nevyplňovat dvakrát" — the Home funnel dates
// are THE dates of the app (`catalogFilterProvider`, written like the
// catalogue date picker): a funnel bike opens its detail with them folded
// ("Změnit") and REZERVOVAT books them; a funnel pick fills Motorky; dates
// picked in Motorky show in the funnel; ✕ clears them everywhere. Photo,
// "n / m" and REZERVOVAT always show the same bike (back on Domů too).
// v5.0.1 (owner): nothing is preselected — without given dates no chip is
// on and the card shows the bikes without a range; a new visit of Domů
// starts at the first bike of a new order.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/currency.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/booking/booking_provider.dart';
import 'package:motogo_app/features/booking/booking_quote.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_detail_page.dart';
import 'package:motogo_app/features/catalog/moto_model.dart' show BookedDateRange;
import 'package:motogo_app/features/home/v2/funnel_carousel_v2.dart';
import 'package:motogo_app/features/home/v2/funnel_provider.dart';
import 'package:motogo_app/features/home/v2/home_funnel_parts.dart';
import 'package:motogo_app/features/home/v2/home_funnel_v2.dart';
import 'package:motogo_app/features/home/v2/home_screen_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_catalog.dart' show registerCatalogStrings;
import '../support/fakes_home.dart';
import '../support/v2_harness.dart';

String _cs(String key) => translations['cs']![key]!;

final _two = kMotos.take(2).toList();
const _funnel = SingleChildScrollView(child: HomeFunnelV2());

ProviderContainer _c(WidgetTester t) => ProviderScope.containerOf(t.element(find.byType(HomeFunnelV2)));

(DateTime?, DateTime?) _dates(ProviderContainer c) =>
    (c.read(catalogFilterProvider).startDate, c.read(catalogFilterProvider).endDate);

Finder _sem(bool Function(SemanticsProperties p) test) =>
    find.byWidgetPredicate((w) => w is Semantics && test(w.properties));

bool _chipOn(WidgetTester t, String label) => t
    .widgetList<Semantics>(_sem((p) => (p.label ?? '').startsWith('$label, ')))
    .any((s) => s.properties.selected == true);

Future<void> _frames(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _end(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 2));
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerHomeStrings();
    registerCatalogStrings();
    mockPathProvider();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MgMotion.resetSession();
  });

  test('given dates → funnel selection (past = not given)', () {
    final now = DateTime.now();
    final p = funnelPresets(now);
    expect(funnelGivenRange(null, now), isNull);
    expect(funnelGivenRange(FunnelRange(day(-2), day(1)), now), isNull);
    expect(funnelGivenRange(FunnelRange(day(9), day(12)), now), FunnelRange(day(9), day(12)));
    expect(const FunnelSelection().range(now), isNull, reason: 'v5.0.1: no preselected weekend');
    expect(const FunnelSelection().preset(now), -1);
    expect(FunnelSelection(p.$1).preset(now), 0);
    expect(FunnelSelection(p.$2).preset(now), 1);
    expect(FunnelSelection(FunnelRange(day(9), day(12))).preset(now), 2);
  });

  testWidgets('funnel bike → detail with the dates folded → REZERVOVAT books bike + dates', (t) async {
    t.view.physicalSize = const Size(412, 915) * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final router = GoRouter(initialLocation: '/', routes: [
      GoRoute(path: '/', builder: (c, s) => const Scaffold(body: _funnel)),
      GoRoute(path: '/moto/:id', builder: (c, s) => MotoDetailPage(motoId: s.pathParameters['id']!, showBackButton: true)),
      GoRoute(path: '/booking', builder: (c, s) => const Text('booking')),
    ]);
    final c = ProviderContainer(overrides: [
      rankTokensProvider.overrideWithValue(RankTokens.forLevel(3)),
      rankArcPctProvider.overrideWithValue(50),
      ...homeOverrides(funnel: _two),
      bookedDatesProvider.overrideWith((ref, id) async => const <BookedDateRange>[]),
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
        builder: (ctx, child) => MgV2Scope(enabled: true, child: child!),
      ),
    ));
    await _frames(t);
    final r = funnelPresets(DateTime.now()).$1;
    expect(_dates(c), (null, null), reason: 'nothing given yet');
    await t.tap(find.text(_cs('v2HomeFnPreset1')));
    await _frames(t);
    await t.tap(find.byType(FunnelBikeCard).first);
    await _frames(t);
    expect(router.routerDelegate.currentConfiguration.uri.toString(), '/moto/m-bmw');
    expect(_dates(c), (r.start, r.end));
    expect(c.read(filteredMotoIdsProvider), ['m-bmw', 'm-husq']);
    // Folded summary with "Změnit" — the calendar is not asked again.
    expect(find.text(_cs('v2DetChange')), findsOneWidget);
    final cta = find.byType(MgCta).last;
    await t.ensureVisible(cta);
    await t.pump();
    await t.tap(cta);
    await _frames(t);
    expect(find.text('booking'), findsOneWidget);
    final d = c.read(bookingDraftProvider);
    expect([d.motoId, d.startDate, d.endDate], ['m-bmw', r.start, r.end]);
    await _end(t);
  });

  testWidgets('funnel pick fills Motorky; Motorky dates show in the funnel; ✕ clears both', (t) async {
    await pumpV2(t, _funnel, size: const Size(412, 915), overrides: homeOverrides(funnel: _two));
    await _frames(t);
    final c = _c(t);
    final p = funnelPresets(DateTime.now());
    expect(_chipOn(t, _cs('v2HomeFnPreset1')), isFalse, reason: 'v5.0.1: nothing ticked by default');
    expect(_chipOn(t, _cs('v2HomeFnPreset2')), isFalse);
    await t.tap(find.text(_cs('v2HomeFnPreset2')));
    await _frames(t);
    expect(_dates(c), (p.$2.start, p.$2.end));
    expect(_chipOn(t, _cs('v2HomeFnPreset2')), isTrue);
    expect(find.byType(FunnelDateLine), findsNothing);

    // Picked in Motorky (same provider) → the funnel shows + prices them.
    c.read(catalogFilterProvider.notifier).state = CatalogFilter(startDate: day(9), endDate: day(12));
    await _frames(t);
    final line = t.widget<FunnelDateLine>(find.byType(FunnelDateLine));
    expect(line.range, FunnelRange(day(9), day(12)));
    final q = quoteFor(_two.first, day(9), day(12), loyalty: kLoyalty3).total;
    expect(find.byWidgetPredicate((w) => w is MgCta && w.price == Money.czk(q)), findsOneWidget);

    await t.tap(find.descendant(of: find.byType(FunnelDateLine), matching: _sem((p) => p.label == _cs('v2HomeDateClear'))));
    await _frames(t);
    expect(_dates(c), (null, null));
    expect(find.byType(FunnelDateLine), findsNothing);
    expect(_chipOn(t, _cs('v2HomeFnPreset1')), isFalse);
    expect(_chipOn(t, _cs('v2HomeFnPreset2')), isFalse);
    await _end(t);
  });

  testWidgets('Domů tab reset of the catalogue keeps the dates; a bike tap gives them again', (t) async {
    await pumpV2(t, _funnel, size: const Size(412, 915), overrides: homeOverrides(funnel: _two));
    await _frames(t);
    final c = _c(t);
    final p = funnelPresets(DateTime.now()).$2;
    await t.tap(find.text(_cs('v2HomeFnPreset2')));
    await _frames(t);
    // Same write as onShellTabTap (Domů) / "Bez termínu".
    c.read(catalogFilterProvider.notifier).state = const CatalogFilter();
    await _frames(t);
    expect(_chipOn(t, _cs('v2HomeFnPreset2')), isTrue);
    await t.tap(find.byType(FunnelBikeCard).first);
    await _frames(t);
    expect(_dates(c), (p.start, p.end));
    await _end(t);
  });

  testWidgets('stale (past) catalogue dates are ignored, not shown', (t) async {
    await pumpV2(t, _funnel, size: const Size(412, 915), overrides: [
      ...homeOverrides(funnel: _two),
      catalogFilterProvider.overrideWith((ref) => CatalogFilter(startDate: day(-3), endDate: day(1))),
    ]);
    await _frames(t);
    expect(find.byType(FunnelDateLine), findsNothing);
    expect(_chipOn(t, _cs('v2HomeFnPreset1')), isFalse, reason: 'stale dates = no dates, nothing ticked');
    await _end(t);
  });

  testWidgets('a remount (new visit of Domů) starts at the first bike; new dates → bike 1', (t) async {
    final show = ValueNotifier(true);
    await pumpV2(t, ValueListenableBuilder<bool>(valueListenable: show, builder: (_, v, __) => v ? _funnel : const SizedBox()),
        size: const Size(412, 915), overrides: homeOverrides(funnel: _two));
    await _frames(t);
    final c = _c(t);
    final r = funnelPresets(DateTime.now()).$1;
    await t.tap(find.text(_cs('v2HomeFnPreset1')));
    await _frames(t);
    double page() => t.widget<PageView>(find.byType(PageView)).controller!.page!;
    await t.tap(_sem((p) => p.label == _cs('v2HomeFnNext')).first);
    await _frames(t);
    expect(find.text('2 / 2'), findsOneWidget);
    expect(page(), 1);
    show.value = false;
    await _frames(t);
    show.value = true;
    await _frames(t);
    // v5.0.1 (owner): a new visit = a new order, from its first bike (the
    // pushed detail keeps Domů mounted — see the test below).
    expect(find.text('1 / 2'), findsOneWidget);
    expect(page(), 0);
    final q = quoteFor(_two[0], r.start, r.end, loyalty: kLoyalty3).total;
    expect(find.byWidgetPredicate((w) => w is MgCta && w.price == Money.czk(q)), findsOneWidget,
        reason: 'photo, pager and CTA = the same bike');
    await t.tap(_sem((p) => p.label == _cs('v2HomeFnNext')).first);
    await _frames(t);
    expect(find.text('2 / 2'), findsOneWidget);
    c.read(catalogFilterProvider.notifier).state = CatalogFilter(startDate: day(9), endDate: day(12));
    await _frames(t);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(page(), 0);
    await _end(t);
  });

  // fix:home r3 — giving the range ALREADY shown again (a card tap writes
  // the dates before the detail opens) is the same range: the centred bike
  // stays (photo = "n / m" = CTA = the booked bike).
  testWidgets('same range given again (card tap) keeps the centred bike', (t) async {
    await pumpV2(t, _funnel, size: const Size(412, 915), overrides: homeOverrides(funnel: _two));
    await _frames(t);
    final c = _c(t);
    final r = funnelPresets(DateTime.now()).$1;
    await t.tap(find.text(_cs('v2HomeFnPreset1')));
    await _frames(t);
    double page() => t.widget<PageView>(find.byType(PageView)).controller!.page!;
    await t.tap(_sem((p) => p.label == _cs('v2HomeFnNext')).first);
    await _frames(t);
    expect(find.text('2 / 2'), findsOneWidget);
    // What the card tap writes (homeGiveDates) before the detail opens.
    c.read(catalogFilterProvider.notifier).state =
        c.read(catalogFilterProvider).copyWith(startDate: () => r.start, endDate: () => r.end);
    await _frames(t);
    expect(c.read(funnelSelectionProvider).given, r);
    expect(c.read(funnelCenterProvider), 1);
    expect(page(), 1);
    expect(find.text('2 / 2'), findsOneWidget);
    final q = quoteFor(_two[1], r.start, r.end, loyalty: kLoyalty3).total;
    expect(find.byWidgetPredicate((w) => w is MgCta && w.price == Money.czk(q)), findsOneWidget);
    await _end(t);
  });

  testWidgets('weekend chip → › → tap the centred bike → back → REZERVOVAT books bike 2', (t) async {
    t.view.physicalSize = const Size(412, 915) * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    // Home in a shell (as in the app) → the detail is PUSHED, Domů stays mounted.
    final router = GoRouter(initialLocation: '/', routes: [
      ShellRoute(builder: (c, s, child) => child, routes: [
        GoRoute(path: '/', builder: (c, s) => const Scaffold(body: _funnel)),
      ]),
      GoRoute(path: '/moto/:id', builder: (c, s) => Scaffold(body: Text('moto ${s.pathParameters['id']}'))),
      GoRoute(path: '/booking', builder: (c, s) => const Text('booking')),
    ]);
    final c = ProviderContainer(overrides: [
      rankTokensProvider.overrideWithValue(RankTokens.forLevel(3)),
      rankArcPctProvider.overrideWithValue(50),
      ...homeOverrides(funnel: _two),
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
        builder: (ctx, child) => MgV2Scope(enabled: true, child: child!),
      ),
    ));
    await _frames(t);
    final r = funnelPresets(DateTime.now()).$1;
    expect(_dates(c), (null, null), reason: 'nothing given yet');
    await t.tap(find.text(_cs('v2HomeFnPreset1')));
    await _frames(t);
    await t.tap(_sem((p) => p.label == _cs('v2HomeFnNext')).first);
    await _frames(t);
    await t.tap(find.byWidgetPredicate((w) => w is FunnelBikeCard && w.center));
    await _frames(t);
    expect(find.text('moto m-husq'), findsOneWidget);
    expect(_dates(c), (r.start, r.end));
    router.pop();
    await _frames(t);
    expect(find.text('2 / 2'), findsOneWidget);
    expect(t.widget<PageView>(find.byType(PageView)).controller!.page, 1);
    final q = quoteFor(_two[1], r.start, r.end, loyalty: kLoyalty3).total;
    final cta = find.byWidgetPredicate((w) => w is MgCta && w.price == Money.czk(q));
    expect(cta, findsOneWidget, reason: 'REZERVOVAT shows the price of the bike in the photo');
    await t.ensureVisible(cta);
    await t.pump();
    await t.tap(cta);
    await _frames(t);
    expect(find.text('booking'), findsOneWidget);
    final d = c.read(bookingDraftProvider);
    expect([d.motoId, d.startDate, d.endDate], ['m-husq', r.start, r.end]);
    await _end(t);
  });

  // The given-dates line (from Motorky / calendar) in every language.
  for (final lang in kV2Langs) {
    for (final size in kV2Sizes) {
      final w = size.width.toInt(), h = size.height.toInt();
      testWidgets('home funnel with given dates $lang ${w}x$h', (t) async {
        final key = GlobalKey();
        await pumpV2(t, const HomeScreenV2(), lang: lang, size: size, boundaryKey: key, overrides: [
          ...homeOverrides(funnel: _two),
          catalogFilterProvider.overrideWith((ref) => CatalogFilter(startDate: day(9), endDate: day(12))),
        ]);
        await expectCleanFrames(t);
        expect(find.byType(FunnelDateLine), findsOneWidget);
        await t.pump(const Duration(seconds: 1));
        expect(t.takeException(), isNull);
        await maybeShot(t, key, 'home__carry__given__${lang}__${w}x$h');
      });
    }
  }
}
