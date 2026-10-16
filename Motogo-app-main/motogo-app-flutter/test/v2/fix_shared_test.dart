// fix:shared regressions (verify findings): restore-and-pay on the v2 card,
// kill-switch safe point in MgV2Gate (both looks), shell chrome lifecycle
// (no use-after-dispose, invisible docks, scroll tick), tab semantics and
// the cross-tab back chip, no salmon rank segment, unset rank grey, FAB
// hidden over e-shop CTAs, CMS branch chrome in every language.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/banner_provider.dart';
import 'package:motogo_app/core/feature_flags.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/core/pending_sos_fab_provider.dart';
import 'package:motogo_app/core/v2/chrome/mg_chrome_metrics.dart';
import 'package:motogo_app/core/v2/chrome/mg_dock.dart';
import 'package:motogo_app/core/v2/chrome/mg_fab_avoid.dart';
import 'package:motogo_app/core/v2/flag/v2_gate.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/rank/rank_palette.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/core/v2/shell/app_shell_v2.dart';
import 'package:motogo_app/core/v2/shell/mg_origin_chip.dart';
import 'package:motogo_app/core/v2/shell/shell_nav_map.dart';
import 'package:motogo_app/core/v2/tokens/mg_colors.dart';
import 'package:motogo_app/features/branches/branches_info_provider.dart';
import 'package:motogo_app/features/branches/v2/branch_texts_v2.dart';
import 'package:motogo_app/features/documents/docs_gate_provider.dart';
import 'package:motogo_app/features/home/v2/home_club_parts.dart';
import 'package:motogo_app/features/messages/messages_provider.dart';
import 'package:motogo_app/features/reservations/reservation_provider.dart';
import 'package:motogo_app/features/reservations/v2/reservation_card_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes_reservations.dart';
import 'support/v2_harness.dart';

Widget _page(String name) => Scaffold(body: Center(child: Text(name)));

Widget _dockPage() => const Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: MgDock(child: MgFabAvoid(child: SizedBox(height: 52, child: Text('CTA')))),
      ),
    );

List<Override> _shellOverrides({PendingBooking? pending, AppV2UiNotifier? flag}) => [
      rankTokensProvider.overrideWithValue(RankTokens.forLevel(10)),
      rankArcPctProvider.overrideWithValue(50),
      appV2UiProvider.overrideWith(
          (ref) => flag ?? AppV2UiNotifier(fetch: () async => null, autoRefresh: false, initial: true)),
      bannerProvider.overrideWithValue(const AsyncData(null)),
      pendingBookingFabProvider.overrideWith((ref) => Stream.value(pending)),
      pendingSosFabProvider.overrideWith((ref) => Stream.value(null)),
      paidAfterRestartProvider.overrideWith((ref) async => null),
      reservationsProvider.overrideWith((ref) => Stream.value(const [])),
      docsFabStatusProvider.overrideWith((ref) => Completer<DocsScreenStatus>().future),
      adminUnreadCountProvider.overrideWithValue(0),
    ];

GoRouter _router(String initial) => GoRouter(initialLocation: initial, routes: [
      ShellRoute(
        builder: (_, __, child) => AppShellV2(child: child),
        routes: [
          for (final p in ['/', '/search', '/reservations', '/profile', '/messages', '/booking'])
            GoRoute(path: p, builder: (_, __) => _page('PAGE $p')),
          GoRoute(path: '/routes', builder: (_, __) => _dockPage()),
        ],
      ),
      GoRoute(path: '/login', builder: (_, __) => const Scaffold(body: Text('LOGIN'))),
    ]);

Future<(GoRouter, ProviderContainer)> _pumpShell(WidgetTester tester, String initial,
    {PendingBooking? pending, bool gate = false, AppV2UiNotifier? flag}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(360, 780) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final router = _router(initial);
  final container = ProviderContainer(overrides: _shellOverrides(pending: pending, flag: flag));
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
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
      builder: (c, child) => gate
          ? MgV2Gate(router: router, child: child!)
          : MgV2Scope(enabled: true, child: child!),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return (router, container);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(loadMontserrat);

  group('reservation card (D3 restore-and-pay parity)', () {
    testWidgets('cancelled card: "Obnovit" runs onRestore, never the catalogue', (tester) async {
      var restored = 0, opened = 0;
      await pumpV2(
        tester,
        SingleChildScrollView(
          child: ReservationCardV2(
            reservation: resv('c1', status: 'cancelled', from: 20, to: 22),
            onTap: () => opened++,
            onRestore: () => restored++,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(t(tester.element(find.byType(ReservationCardV2))).tr('restoreBtn')));
      await tester.pump();
      expect(restored, 1);
      expect(opened, 0);
    });

    testWidgets('without onRestore it opens the detail (like ReservationCard)', (tester) async {
      var opened = 0;
      await pumpV2(
        tester,
        SingleChildScrollView(
          child: ReservationCardV2(
            reservation: resv('c2', status: 'cancelled', from: 20, to: 22),
            onTap: () => opened++,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(t(tester.element(find.byType(ReservationCardV2))).tr('restoreBtn')));
      await tester.pump();
      expect(opened, 1);
    });
  });

  group('shell chrome lifecycle', () {
    testWidgets('shell disposed with a dock + avoid zone on screen → no use-after-dispose', (tester) async {
      final (router, _) = await _pumpShell(tester, '/routes');
      expect(find.text('CTA'), findsOneWidget);
      router.go('/login');
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('LOGIN'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('MgShellChrome: calls after dispose are no-ops', () {
      final c = MgShellChrome()..dispose();
      c.reportStrips(10);
      c.reportDock(Object(), 40);
      c.removeDock(Object());
      c.registerZone(Object(), () => null, MgAvoidKind.cta);
      c.removeZone(Object());
      c.scrollIdle();
      c.dispose();
    });

    test('dockHeight skips docks on covered routes; scroll idle does not rebuild layout', () {
      final c = MgShellChrome();
      addTearDown(c.dispose);
      var visible = true;
      c.reportDock(1, 80, visible: () => visible);
      expect(c.dockHeight, 80);
      visible = false;
      expect(c.dockHeight, 0);
      var layoutNotes = 0, ticks = 0;
      c.addListener(() => layoutNotes++);
      c.scrollTick.addListener(() => ticks++);
      c.scrollIdle();
      expect(ticks, 1);
      expect(layoutNotes, 0);
    });
  });

  group('tabs', () {
    testWidgets('tap on the highlighted tab from its sub-route goes to the tab root (approved v2)', (tester) async {
      final (router, _) = await _pumpShell(tester, '/messages');
      await tester.tap(find.text('Profil'));
      await _settle(tester);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/profile');
    });

    testWidgets('cross-tab back chip: shown on its tab, gone after a tab switch', (tester) async {
      final (router, c) = await _pumpShell(tester, '/');
      c.read(v2TabOriginProvider.notifier).state = const V2TabOrigin(tab: 1, route: '/', labelKey: 'v2TabHome');
      router.go('/search');
      await _settle(tester);
      expect(c.read(v2TabOriginProvider)?.tab, 1);
      await tester.tap(find.text('Rezervace'));
      await _settle(tester);
      expect(c.read(v2TabOriginProvider), isNull);
    });

    testWidgets('the chip goes back to its origin', (tester) async {
      String? went;
      final router = GoRouter(initialLocation: '/', routes: [
        GoRoute(path: '/', builder: (_, __) => const Scaffold(body: MgOriginChip(tab: 1))),
        GoRoute(path: '/back', builder: (_, __) {
          went = '/back';
          return _page('BACK');
        }),
      ]);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(v2TabOriginProvider.notifier).state =
          const V2TabOrigin(tab: 1, route: '/back', labelKey: 'v2OriginBranch');
      await tester.pumpWidget(UncontrolledProviderScope(
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
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('Pobočka'));
      await _settle(tester);
      expect(went, '/back');
      expect(c.read(v2TabOriginProvider), isNull);
    });

    testWidgets('the shell publishes the Rezervace dot for the nav outside it', (tester) async {
      final pending = PendingBooking(id: 'b1', totalPrice: 12027, createdAt: DateTime.now());
      final (_, c) = await _pumpShell(tester, '/', pending: pending);
      await _settle(tester);
      expect(c.read(v2BookingsNeedActionProvider), isTrue);
    });
  });

  group('kill-switch safe point (MgV2Gate)', () {
    testWidgets('remote OFF applies right after the cold-start fetch on a tab root', (tester) async {
      final flag = AppV2UiNotifier(fetch: () async => false, initial: true);
      final (_, c) = await _pumpShell(tester, '/', gate: true, flag: flag);
      await _settle(tester);
      expect(c.read(appV2UiProvider), isFalse);
    });

    testWidgets('inside a flow it waits; landing on a tab root applies it', (tester) async {
      final flag = AppV2UiNotifier(fetch: () async => false, initial: true);
      final (router, c) = await _pumpShell(tester, '/booking', gate: true, flag: flag);
      await _settle(tester);
      expect(c.read(appV2UiProvider), isTrue);
      router.go('/reservations');
      await _settle(tester);
      expect(c.read(appV2UiProvider), isFalse);
    });

    testWidgets('a running payment blocks it', (tester) async {
      final flag = AppV2UiNotifier(fetch: () async => false, initial: true, paymentRunning: () => true);
      final (_, c) = await _pumpShell(tester, '/', gate: true, flag: flag);
      await _settle(tester);
      expect(c.read(appV2UiProvider), isTrue);
    });
  });

  group('rank colours', () {
    test('the fromJson default grey is "unset" on every level', () {
      for (var l = 1; l <= 20; l++) {
        expect(resolveRankHex(l, '#9CA3AF'), kRankRampHex[l - 1], reason: 'level $l');
      }
    });

    test('club tier "next" segment: neutral fill + full rank outline, never a lightened rank colour', () {
      for (var l = 1; l <= 20; l++) {
        final r = RankTokens.forLevel(l);
        final d = clubTierSegment(r, lit: false, next: true);
        expect(d.color, MgColors.inkA(0.18), reason: 'level $l');
        final b = d.border as Border;
        expect(b.top.color, r.uiLight, reason: 'level $l');
        final hsl = HSLColor.fromColor(d.color!);
        final pinkish = hsl.hue >= 232 && hsl.hue <= 345 && hsl.saturation > 0.2;
        final salmon = (hsl.hue < 20 || hsl.hue > 340) && hsl.lightness > 0.7 && hsl.saturation > 0.2;
        expect(pinkish || salmon, isFalse, reason: 'level $l');
      }
    });
  });

  test('AI button hidden over the old e-shop / voucher CTAs', () {
    expect(v2FabHiddenFor('/shop'), isTrue);
    expect(v2FabHiddenFor('/shop/abc'), isTrue);
    expect(v2FabHiddenFor('/voucher'), isTrue);
    expect(v2FabHiddenFor('/profile'), isFalse);
  });

  test('Pobočky chrome from CMS defaults is never Czech in another language', () {
    final en = v2BranchTexts(const AppTranslations('en'), branchesInfoDefaults);
    expect(en['detail_button'], const AppTranslations('en').tr('v2BrDetail'));
    expect(en['cta.title'], isNot(branchesInfoDefaults['cta.title']));
    expect(en['branches.0.title'], branchesInfoDefaults['branches.0.title']); // proper name stays
    final cs = v2BranchTexts(const AppTranslations('cs'), branchesInfoDefaults);
    expect(cs['cta.title'], branchesInfoDefaults['cta.title']);
    final edited = v2BranchTexts(const AppTranslations('de'), {...branchesInfoDefaults, 'cta.title': 'Eigener Text'});
    expect(edited['cta.title'], 'Eigener Text');
  });
}
