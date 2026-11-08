// AppShellV2 + a real GoRouter with caller routes and the catalog fakes —
// for the hide-on-scroll / one-bike-per-screen tests (owner 2026-11-08).
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
import 'package:motogo_app/core/v2/chrome/mg_hide_on_scroll.dart';
import 'package:motogo_app/core/v2/chrome/mg_nav_band.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/core/v2/shell/app_shell_v2.dart';
import 'package:motogo_app/features/documents/docs_gate_provider.dart';
import 'package:motogo_app/features/messages/messages_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes_catalog.dart';
import 'v2_harness.dart';

/// Pumps the v2 shell at [initial] with [routes] (path → page) inside it.
/// [top] / [bottom] = the safe-area insets in logical px.
Future<GoRouter> pumpBarsShell(
  WidgetTester tester,
  String initial,
  Map<String, Widget Function(GoRouterState)> routes, {
  List<Override> overrides = const [],
  BannerData? banner,
  PendingBooking? pending,
  bool reducedMotion = false,
  bool screenReader = false,
  Size size = const Size(390, 844),
  double top = 47,
  double bottom = 34,
  String lang = 'cs',
}) async {
  SharedPreferences.setMockInitialValues(const {});
  registerCatalogStrings();
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.view.padding = FakeViewPadding(top: top * 2, bottom: bottom * 2);
  tester.view.viewPadding = FakeViewPadding(top: top * 2, bottom: bottom * 2);
  addTearDown(tester.view.reset);
  final router = GoRouter(initialLocation: initial, routes: [
    ShellRoute(
      // As router.dart: pushes / pops on the shell navigator reset the bars,
      // a popup on top is not the page.
      observers: [MgBarsRouteObserver()],
      builder: (_, __, child) => AppShellV2(child: child),
      routes: [for (final e in routes.entries) GoRoute(path: e.key, builder: (_, s) => e.value(s))],
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      rankTokensProvider.overrideWithValue(RankTokens.forLevel(3)),
      rankArcPctProvider.overrideWithValue(50),
      appV2UiProvider.overrideWith((ref) => AppV2UiNotifier(fetch: () async => null, autoRefresh: false, initial: true)),
      pendingBookingFabProvider.overrideWith((ref) => Stream.value(pending)),
      pendingSosFabProvider.overrideWith((ref) => Stream.value(null)),
      paidAfterRestartProvider.overrideWith((ref) async => null),
      docsFabStatusProvider.overrideWith((ref) => Completer<DocsScreenStatus>().future),
      adminUnreadCountProvider.overrideWithValue(0),
      ...catalogOverrides(banner: banner),
      ...overrides,
    ],
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      locale: Locale(lang),
      supportedLocales: supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: v2TestTheme(),
      builder: (c, child) => MgV2Scope(
        enabled: true,
        child: MediaQuery(
          data: MediaQuery.of(c).copyWith(
            textScaler: TextScaler.noScaling,
            disableAnimations: reducedMotion,
            accessibleNavigation: screenReader,
          ),
          child: child!,
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return router;
}

/// Whether the shell nav is folded to its band right now.
bool navFolded(WidgetTester tester) => tester.widget<MgNavBand>(find.byType(MgNavBand)).folded;

/// Lets the 300 ms chrome motion finish.
Future<void> settleChrome(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

/// A drag of the finger by [dy] px over [finder] with pauses (release
/// velocity ≈ 0 → no fling).
Future<void> slowDrag(WidgetTester tester, Finder finder, double dy) async {
  final g = await tester.startGesture(tester.getCenter(finder));
  const steps = 10;
  for (var i = 0; i < steps; i++) {
    await g.moveBy(Offset(0, dy / steps));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump(const Duration(milliseconds: 300));
  await g.up();
  await tester.pump();
}
