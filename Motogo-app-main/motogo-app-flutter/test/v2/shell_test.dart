// AppShellV2 in a real GoRouter: 5-tab nav on tab roots (also for pushed
// routes — location comes from the router delegate), hidden in focused
// flows, tab taps through the shared onShellTabTap, re-tap = reselect,
// the same floating panels as v2 strips, banner rules.
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
import 'package:motogo_app/core/v2/chrome/mg_ai_fab.dart';
import 'package:motogo_app/core/v2/chrome/mg_status_strip.dart';
import 'package:motogo_app/core/v2/chrome/v2_nav_bar.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/core/v2/shell/app_shell_v2.dart';
import 'package:motogo_app/core/v2/shell/shell_nav_map.dart';
import 'package:motogo_app/features/documents/docs_gate_provider.dart';
import 'package:motogo_app/features/messages/messages_provider.dart';
import 'package:motogo_app/features/reservations/reservation_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/v2_harness.dart';

Widget _page(String name) => Scaffold(body: Center(child: Text(name)));

GoRouter _router(String initial) => GoRouter(
      initialLocation: initial,
      routes: [
        ShellRoute(
          builder: (_, __, child) => AppShellV2(child: child),
          routes: [
            for (final p in ['/', '/search', '/reservations', '/routes', '/profile', '/booking', '/messages', '/cart'])
              GoRoute(path: p, builder: (_, __) => _page('PAGE $p')),
            GoRoute(path: '/moto/:id', builder: (_, s) => _page('MOTO ${s.pathParameters['id']}')),
          ],
        ),
      ],
    );

Future<GoRouter> _pump(WidgetTester tester, String initial,
    {PendingBooking? pending, int unread = 0, bool banner = false}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(360, 780) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final router = _router(initial);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      rankTokensProvider.overrideWithValue(RankTokens.forLevel(10)),
      rankArcPctProvider.overrideWithValue(50),
      appV2UiProvider.overrideWith((ref) => AppV2UiNotifier(fetch: () async => null, autoRefresh: false, initial: true)),
      bannerProvider.overrideWithValue(AsyncData(banner
          ? const BannerData(enabled: true, text: 'Sezóna 2027 začíná', bg: Colors.black, color: Colors.white)
          : null)),
      pendingBookingFabProvider.overrideWith((ref) => Stream.value(pending)),
      pendingSosFabProvider.overrideWith((ref) => Stream.value(null)),
      paidAfterRestartProvider.overrideWith((ref) async => null),
      reservationsProvider.overrideWith((ref) => Stream.value(const [])),
      docsFabStatusProvider.overrideWith((ref) => Completer<DocsScreenStatus>().future),
      adminUnreadCountProvider.overrideWithValue(unread),
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
      builder: (c, child) => MgV2Scope(
        enabled: true,
        child: MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.noScaling), child: child!),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return router;
}

void main() {
  setUpAll(loadMontserrat);

  test('nav map', () {
    expect(v2TabIndexFor('/'), 0);
    expect(v2TabIndexFor('/moto/abc'), 1);
    expect(v2TabIndexFor('/payment'), 1);
    expect(v2TabIndexFor('/reservations/x/edit'), 2);
    expect(v2TabIndexFor('/sos/theft'), 2);
    expect(v2TabIndexFor('/routes-list'), 3);
    expect(v2TabIndexFor('/places-map'), 3);
    expect(v2TabIndexFor('/messages?n=1'), 4);
    expect(v2TabIndexFor('/ai-agent'), 4);
    expect(v2NavHiddenFor('/moto/abc'), isTrue);
    expect(v2NavHiddenFor('/reservations/x/edit'), isTrue);
    expect(v2NavHiddenFor('/reservations/x'), isFalse);
    expect(v2NavHiddenFor('/messages/abc'), isTrue);
    expect(v2NavHiddenFor('/messages'), isFalse);
    expect(v2FabHiddenFor('/routes'), isTrue);
    expect(v2FabHiddenFor('/routes/abc'), isTrue);
    expect(v2FabHiddenFor('/reservations'), isFalse);
    expect(v2FabHiddenFor('/sos'), isTrue);
  });

  testWidgets('tab root: nav + AI button; tapping a tab navigates', (tester) async {
    final router = await _pump(tester, '/');
    expect(find.byType(V2NavBar), findsOneWidget);
    expect(find.text('PAGE /'), findsOneWidget);
    await tester.tap(find.text('Rezervace'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('PAGE /reservations'), findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/reservations');
    await tester.tap(find.text('Profil'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('PAGE /profile'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('re-tap of the active tab root bumps the reselect provider', (tester) async {
    await _pump(tester, '/search');
    final container = ProviderScope.containerOf(tester.element(find.byType(V2NavBar)));
    await tester.tap(find.text('Motorky'));
    await tester.pump();
    expect(container.read(v2TabReselectProvider).$1, 1);
  });

  testWidgets('pushed focused flow hides the nav (location from the delegate)', (tester) async {
    final router = await _pump(tester, '/search');
    unawaited(router.push('/moto/abc'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('MOTO abc'), findsOneWidget);
    expect(find.byType(V2NavBar), findsNothing);
    router.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(V2NavBar), findsOneWidget);
  });

  testWidgets('pending booking → v2 payment strip + Rezervace dot; same countdown text', (tester) async {
    final pending = PendingBooking(id: 'b1', totalPrice: 12027, createdAt: DateTime.now());
    await _pump(tester, '/', pending: pending, unread: 2);
    expect(find.byType(MgStatusStrip), findsOneWidget);
    expect(find.text('Dokončit rezervaci'), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // Profil badge
    expect(find.byType(MgAiFab), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('banner: shown on other tab roots, left to the v2 header on / and /search', (tester) async {
    await _pump(tester, '/', banner: true);
    expect(find.text('Sezóna 2027 začíná'), findsNothing);
    await tester.tap(find.text('Rezervace'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Sezóna 2027 začíná'), findsWidgets);
  });
}
