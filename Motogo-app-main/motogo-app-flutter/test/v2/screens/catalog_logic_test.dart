// v2 catalog behaviour guards (PLAN §0.1 / §5.5 / §5.6): the v2 screens
// call the SAME actions as the old ones — card tap (sibling ids + detail),
// REZERVOVAT (PM-3: identical draft from the old and the v2 detail), the
// date sheet writes `catalogFilterProvider` like the old screen, the
// calculator hands its pickup time to the draft; `quoteFor` == the booking
// form's `priceBreakdownProvider`; flag OFF = the old trees; ext_52 strings.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/i18n/translations_ext_52_v2_catalog_a.dart';
import 'package:motogo_app/core/i18n/translations_ext_52_v2_catalog_b.dart';
import 'package:motogo_app/core/i18n/translations_ext_52_v2_catalog_c.dart';
import 'package:motogo_app/core/i18n/translations_ext_52_v2_catalog_d.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/core/v2/widgets/mg_chips.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/booking/booking_provider.dart';
import 'package:motogo_app/features/booking/booking_quote.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_detail_page.dart';
import 'package:motogo_app/features/catalog/moto_detail_screen.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_state.dart';
import 'package:motogo_app/features/catalog/v2/catalog_date_sheet_v2.dart';
import 'package:motogo_app/features/catalog/v2/catalog_mode.dart';
import 'package:motogo_app/features/catalog/v2/catalog_text.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_pager_v2.dart';
import 'package:motogo_app/features/catalog/v2/detail/moto_detail_view_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';
import 'package:motogo_app/features/catalog/widgets/price_footer.dart';
import 'package:motogo_app/features/loyalty/loyalty_provider.dart';

import '../support/fakes_catalog.dart';
import '../support/v2_harness.dart';

const _profile = {
  'license_group': ['A', 'B'],
  'gear_sizes': {
    'rider': {'helmet': 'L', 'gloves': 'M', 'jacket': 'L', 'pants': 'M', 'boots': '43'},
    'rider_own': false,
  },
};

/// The screen at its real path + stub targets; returns the container.
Future<(GoRouter, ProviderContainer)> _pumpRouted(
  WidgetTester t, {
  required String initial,
  required Widget Function(GoRouterState) screen,
  required String path,
  required List<Override> overrides,
  bool v2 = true,
}) async {
  t.view.physicalSize = const Size(412, 915) * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final router = GoRouter(initialLocation: initial, routes: [
    GoRoute(path: path, builder: (c, s) => screen(s)),
    if (path != '/search') GoRoute(path: '/search', builder: (c, s) => const Text('search')),
    if (path != '/moto/:id') GoRoute(path: '/moto/:id', builder: (c, s) => Text('detail:${s.pathParameters['id']}')),
    GoRoute(path: '/booking', builder: (c, s) => const Text('booking')),
  ]);
  final container = ProviderContainer(overrides: [
    rankTokensProvider.overrideWithValue(RankTokens.forLevel(3)),
    rankArcPctProvider.overrideWithValue(50),
    ...overrides,
  ]);
  addTearDown(container.dispose);
  await t.pumpWidget(UncontrolledProviderScope(
    container: container,
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
      builder: (c, child) => MgV2Scope(enabled: v2, child: child!),
    ),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 800));
  return (router, container);
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerCatalogStrings();
  });
  setUp(MgMotion.resetSession);
  final (ws, we) = futureWeekend();
  final dated = CatalogFilter(startDate: ws, endDate: we);

  testWidgets('card CTA → detail with the shown (sorted) sibling ids', (t) async {
    final (router, c) = await _pumpRouted(t,
        initial: '/search',
        path: '/search',
        screen: (_) => const MotorkyScreenV2(),
        overrides: catalogOverrides(filter: dated, filtered: [kBmw, kHusq, kKids]));
    await t.tap(find.byType(MgCta).first);
    await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(find.text('detail:m-bmw'), findsOneWidget);
    expect(c.read(filteredMotoIdsProvider), ['m-bmw', 'm-husq', 'm-kid']);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('date sheet: preset writes the filter, ✕ in the pill clears it', (t) async {
    final (_, c) = await _pumpRouted(t,
        initial: '/search', path: '/search', screen: (_) => const MotorkyScreenV2(), overrides: catalogOverrides());
    showCatalogDateSheet(t.element(find.byType(MotorkyScreenV2)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    final tr = AppTranslations.of('cs');
    await t.tap(find.widgetWithText(MgChoiceChip, tr.tr('v2CatPresetWeekend')));
    await t.pump();
    final w = catWeekend(DateTime.now());
    expect(c.read(catalogFilterProvider).startDate, w.$1);
    expect(c.read(catalogFilterProvider).endDate, w.$2);
    await t.tap(find.widgetWithText(MgChoiceChip, tr.tr('v2CatPresetNone')));
    await t.pump();
    expect(c.read(catalogFilterProvider).startDate, isNull);
    expect(c.read(catalogFilterProvider).endDate, isNull);
  });

  Future<BookingDraft> reserveFromDetail(WidgetTester t, {required bool v2}) async {
    final (router, c) = await _pumpRouted(t,
        initial: '/moto/m-bmw',
        path: '/moto/:id',
        v2: v2,
        screen: (s) => MotoDetailPage(motoId: s.pathParameters['id']!, showBackButton: true),
        overrides: catalogOverrides(filter: dated, profile: _profile));
    await t.pump(const Duration(milliseconds: 300));
    if (v2) {
      await t.tap(find.byType(MgCta));
    } else {
      final btn = find.widgetWithText(ElevatedButton, AppTranslations.of('cs').tr('detailReserveBtn'));
      await t.scrollUntilVisible(btn, 300, scrollable: find.byType(Scrollable).first);
      await t.pump();
      await t.tap(btn);
    }
    await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(find.text('booking'), findsOneWidget);
    expect(c.read(bookingMotoProvider)?.id, 'm-bmw');
    return c.read(bookingDraftProvider);
  }

  testWidgets('detail REZERVOVAT: v2 builds the SAME draft as the old detail (PM-3)', (t) async {
    // The OLD PriceFooter row overflows with Montserrat at 412 px (pre-existing
    // old-UI layout, untouched by v2) — ignore only that while driving it.
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.toString().contains('overflowed')) prev?.call(d);
    };
    final old = await reserveFromDetail(t, v2: false);
    FlutterError.onError = prev;
    final neu = await reserveFromDetail(t, v2: true);
    for (final d in [old, neu]) {
      expect(d.motoId, 'm-bmw');
      expect(d.startDate, ws);
      expect(d.endDate, we);
      expect(d.pickupTime, isNull);
      expect(d.helmetSize, 'L');
      expect(d.jacketSize, 'L');
      expect(d.bootsSize, isNull); // boots are never prefilled
    }
    expect(neu.motoName, old.motoName);
    // Unmount while the clock still runs: Riverpod's autoDispose (booked
    // dates) and the one-shot reveal delays schedule short timers.
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
    expect([neu.glovesSize, neu.pantsSize, neu.ownGear, neu.motoImage], [old.glovesSize, old.pantsSize, old.ownGear, old.motoImage]);
  });

  testWidgets('calculator REZERVOVAT hands the 12:00 pickup to the draft', (t) async {
    final (_, c) = await _pumpRouted(t,
        initial: '/search',
        path: '/search',
        screen: (_) => const MotorkyScreenV2(),
        overrides: [
          ...catalogOverrides(calc: CalcState(motoId: 'm-bmw', start: ws, end: we, pickupTime: '12:00'), profile: _profile),
          catalogModeProvider.overrideWith((ref) => CatalogMode.calc),
        ]);
    final cta = find.byType(MgCta).last;
    await t.ensureVisible(cta);
    await t.pump();
    await t.tap(cta);
    await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(find.text('booking'), findsOneWidget);
    final d = c.read(bookingDraftProvider);
    expect([d.motoId, d.startDate, d.endDate, d.pickupTime], ['m-bmw', ws, we, '12:00']);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  });

  group('quoteFor == booking form price (priceBreakdownProvider)', () {
    LoyaltyStatus? rank(int lv) =>
        lv == 0 ? null : LoyaltyStatus(level: lv, percent: lv, rankName: 'R$lv', colorHex: '#37CF63', qualifyingCount: lv * 2);
    for (final m in [kBmw, kHusq, kShotgun]) {
      for (final lv in [0, 2, 3, 17, 20]) {
        for (final time in [null, '12:00']) {
          for (final days in [1, 2, 3, 7]) {
            test('${m.id} rank $lv ${time ?? '09:00'} $days d', () {
              final s = ws, e = DateTime(ws.year, ws.month, ws.day + days - 1);
              final c = ProviderContainer(overrides: [
                bookingDraftProvider.overrideWith((ref) => BookingDraft(motoId: m.id, startDate: s, endDate: e, pickupTime: time)),
                bookingMotoProvider.overrideWith((ref) => m),
                loyaltyStatusProvider.overrideWith((ref) async => rank(lv)),
              ]);
              addTearDown(c.dispose);
              return c.read(loyaltyStatusProvider.future).then((_) {
                expect(quoteFor(m, s, e, pickupTime: time, loyalty: rank(lv)).total, c.read(priceBreakdownProvider).total);
              });
            });
          }
        }
      }
    }
    test('V21 §3.3 check values (BMW pá–ne, rank 3)', () {
      final fri = DateTime(2026, 10, 23), sun = DateTime(2026, 10, 25);
      expect(quoteFor(kBmw, fri, sun, loyalty: kLoyalty3).total, 11893);
      expect(quoteFor(kBmw, fri, sun, pickupTime: '12:00', loyalty: kLoyalty3).total, 10189);
      expect(quoteFor(kBmw, fri, sun).total, 12261);
    });
  });

  group('flag OFF = old trees', () {
    testWidgets('detail page', (t) async {
      await pumpV2(t, const MotoDetailPage(motoId: 'm-bmw', showBackButton: true),
          v2: false, size: const Size(412, 3200), overrides: catalogOverrides());
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(MotoDetailV2View), findsNothing);
      expect(find.byType(PriceFooter), findsOneWidget);
    });
    testWidgets('detail pager', (t) async {
      await pumpV2(t, const MotoDetailScreen(motoId: 'm-bmw'), v2: false, overrides: [
        ...catalogOverrides(),
        filteredMotoIdsProvider.overrideWith((ref) => ['m-bmw', 'm-husq']),
      ]);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(MotoDetailPagerV2View), findsNothing);
      expect(find.text('1 / 2'), findsOneWidget);
    });
  });

  group('helpers', () {
    test('weekend presets', () {
      expect(catWeekend(DateTime(2026, 10, 21)), (DateTime(2026, 10, 23), DateTime(2026, 10, 25))); // Wed
      expect(catWeekend(DateTime(2026, 10, 24)), (DateTime(2026, 10, 24), DateTime(2026, 10, 25))); // Sat
      expect(catWeekend(DateTime(2026, 10, 21), skip: 1), (DateTime(2026, 10, 30), DateTime(2026, 11, 1)));
      expect(catWeekend(DateTime(2026, 10, 25), skip: 1), (DateTime(2026, 10, 30), DateTime(2026, 11, 1))); // Sun, DST end
    });
    test('count plurals', () {
      final cs = AppTranslations.of('cs');
      expect([catCount(cs, 1), catCount(cs, 3), catCount(cs, 12)], ['1 motorka', '3 motorky', '12 motorek']);
      expect(catCount(AppTranslations.of('uk'), 21), '21 мотоцикл');
    });
    test('licence label = old card rule', () {
      final cs = AppTranslations.of('cs');
      expect(catLicenseLabel(cs, kKids), cs.tr('catalogNoLicense'));
      expect(catLicenseLabel(cs, kHusq), '${cs.tr('motoCardLicensePrefix')}A2 / A');
    });
  });

  test('ext_52: 8 languages, same keys + placeholders, v2 prefix, no emoji, tykání', () {
    final all = <String, Map<String, String>>{};
    for (final p in [translationsExt52V2CatalogA, translationsExt52V2CatalogB, translationsExt52V2CatalogC, translationsExt52V2CatalogD]) {
      all.addAll(p);
    }
    expect(all.keys.toSet(), kV2Langs.toSet());
    final keys = all['cs']!.keys.toSet();
    final ph = RegExp(r'\{[a-zA-Z]+\}');
    final emoji = RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true);
    for (final l in kV2Langs) {
      expect(all[l]!.keys.toSet(), keys, reason: l);
      for (final k in keys) {
        final v = all[l]![k]!;
        expect(k.startsWith('v2'), isTrue);
        expect(v.trim(), isNotEmpty, reason: '$l $k');
        expect(ph.allMatches(v).map((m) => m[0]).toSet(), ph.allMatches(all['cs']![k]!).map((m) => m[0]).toSet(), reason: '$l $k');
        expect(emoji.hasMatch(v), isFalse, reason: '$l $k');
      }
    }
    final formal = RegExp(r'\b(Vaše|Váš|Vám|Vás|jste|Potřebujete|Můžete|Klepněte|Vyberte|Zkuste)\b');
    for (final k in keys) {
      expect(formal.hasMatch(all['cs']![k]!), isFalse, reason: k);
    }
  });
}
