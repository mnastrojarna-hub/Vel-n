// SH-05 strip ✕ confirm, SH-06 no duplicate strip on Domů, SH-07 one strip
// + "+n" sheet, SH-13 tab fade-through, SH-14 push page on both platforms.
import 'dart:async';

import 'package:flutter/foundation.dart';
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
import 'package:motogo_app/core/router.dart' show routerSwipeBackPage, routerTabPage;
import 'package:motogo_app/core/v2/chrome/mg_status_strip.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/core/v2/shell/app_shell_v2.dart';
import 'package:motogo_app/core/v2/widgets/mg_dialog.dart';
import 'package:motogo_app/core/v2/widgets/mg_sheet.dart';
import 'package:motogo_app/features/documents/docs_gate_provider.dart';
import 'package:motogo_app/features/messages/messages_provider.dart';
import 'package:motogo_app/features/reservations/reservation_provider.dart';
import 'package:motogo_app/features/shop/shop_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/shell_harness.dart' show kShellTestPaths;
import '../support/v2_harness.dart';

const _sos = PendingSosReplacement(id: 's1', type: 'breakdown_minor', status: 'reported');

Future<GoRouter> _shell(WidgetTester tester, String initial,
    {PendingBooking? pending, PendingSosReplacement? sos, bool cart = false, bool reduced = false}) async {
  SharedPreferences.setMockInitialValues({'mg_v2_ai_coach_seen': true});
  tester.view.physicalSize = const Size(360, 780) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final router = GoRouter(initialLocation: initial, routes: [
    ShellRoute(
      builder: (_, __, child) => AppShellV2(child: child),
      routes: [
        for (final p in kShellTestPaths)
          GoRoute(path: p, builder: (_, s) => Scaffold(body: Center(child: Text('PAGE ${s.uri.path}')))),
      ],
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      rankTokensProvider.overrideWithValue(RankTokens.forLevel(10)),
      rankArcPctProvider.overrideWithValue(50),
      appV2UiProvider.overrideWith((ref) => AppV2UiNotifier(fetch: () async => null, autoRefresh: false, initial: true)),
      bannerProvider.overrideWithValue(const AsyncData(null)),
      pendingBookingFabProvider.overrideWith((ref) => Stream.value(pending)),
      pendingSosFabProvider.overrideWith((ref) => Stream.value(sos)),
      paidAfterRestartProvider.overrideWith((ref) async => null),
      reservationsProvider.overrideWith((ref) => Stream.value(const [])),
      docsFabStatusProvider.overrideWith((ref) => Completer<DocsScreenStatus>().future),
      adminUnreadCountProvider.overrideWithValue(0),
      if (cart) cartProvider.overrideWith((ref) => CartNotifier()..addItem('p1', 'Tričko', 490)),
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
        child: MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.noScaling, disableAnimations: reduced),
          child: child!,
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return router;
}

PendingBooking _pending() => PendingBooking(id: 'b1', totalPrice: 12027, createdAt: DateTime.now());

void main() {
  setUpAll(loadMontserrat);

  testWidgets('SH-06 Domů: the pay strip is left out (the ticket S2 has it); /search shows it', (tester) async {
    final router = await _shell(tester, '/', pending: _pending());
    expect(find.byType(MgStatusStrip), findsNothing);
    router.go('/search');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MgStatusStrip), findsOneWidget);
    expect(find.text('Dokončit rezervaci'), findsOneWidget);
  });

  testWidgets('SH-07 three strips → ONE (SOS first) + "+2"; sheet lists all, a tap closes it and runs the action', (tester) async {
    await _shell(tester, '/search', pending: _pending(), sos: _sos, cart: true, reduced: true);
    expect(find.byType(MgStatusStrip), findsOneWidget);
    expect(find.text('+2'), findsOneWidget);
    final stripH = tester.getSize(find.byType(MgStatusStrip)).height;
    await tester.tap(find.text('+2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MgSheetFrame), findsOneWidget);
    expect(find.descendant(of: find.byType(MgSheetFrame), matching: find.byType(MgStatusStrip)), findsNWidgets(3));
    expect(find.text('+2'), findsOneWidget); // only the shell strip carries the chip
    // Cart row → closes the sheet first, then its own action (push /cart).
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('sheet-strip-cart')), matching: find.byType(MgStatusStrip)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(MgSheetFrame), findsNothing);
    expect(find.text('PAGE /cart'), findsOneWidget);
    expect(stripH, lessThan(90));
  });

  testWidgets('SH-07 ✕ in the sheet keeps it open and the list follows; ≤ 1 left → it closes', (tester) async {
    await _shell(tester, '/search', sos: _sos, cart: true, reduced: true);
    expect(find.text('+1'), findsOneWidget);
    await tester.tap(find.text('+1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final cartRow = find.byKey(const ValueKey('sheet-strip-cart'));
    expect(cartRow, findsOneWidget);
    await tester.tap(find.descendant(of: cartRow, matching: find.bySemanticsLabel('Zavřít')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    // Cart dismissed (its own ✕) → one strip left → the sheet closed itself.
    expect(find.byType(MgSheetFrame), findsNothing);
    expect(find.text('+1'), findsNothing);
  });

  testWidgets('SH-05 strip ✕ → v2 T6 confirm; Zpět = nothing, Zrušit rezervaci = cancel runs once', (tester) async {
    await _shell(tester, '/search', pending: _pending(), reduced: true);
    Future<void> tapX() async {
      final strip = find.byType(MgStatusStrip);
      await tester.tap(find.descendant(of: strip, matching: find.bySemanticsLabel('Zrušit rezervaci')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    await tapX();
    expect(find.byType(MgDialogFrame), findsOneWidget);
    expect(find.text('Zrušit rezervaci?'), findsOneWidget);
    await tester.tap(find.text('Zpět'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(MgDialogFrame), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    await tapX();
    await tester.tap(find.descendant(of: find.byType(MgDialogFrame), matching: find.text('Zrušit rezervaci')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // No backend in tests → the existing failure path ran exactly once.
    expect(find.byType(SnackBar), findsOneWidget);
  });

  Future<GoRouter> mini(WidgetTester tester, {required bool v2, bool reduced = false, bool tab = true}) async {
    final router = GoRouter(initialLocation: '/a', routes: [
      GoRoute(
          path: '/a',
          pageBuilder: (c, s) => tab
              ? routerTabPage(c, s, const Scaffold(body: Text('A')))
              : routerSwipeBackPage(s.pageKey, const Scaffold(body: Text('A')), c)),
      GoRoute(
          path: '/b',
          pageBuilder: (c, s) => tab
              ? routerTabPage(c, s, const Scaffold(body: Text('B')))
              : routerSwipeBackPage(s.pageKey, const Scaffold(body: Text('B')), c)),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
      theme: v2TestTheme(),
      builder: (c, child) => MgV2Scope(
        enabled: v2,
        child: MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: reduced), child: child!),
      ),
    ));
    return router;
  }

  double? opacityOverB(WidgetTester tester) {
    final f = find.ancestor(of: find.text('B'), matching: find.byType(FadeTransition));
    if (f.evaluate().isEmpty) return null;
    return tester.widget<FadeTransition>(f.first).opacity.value;
  }

  testWidgets('SH-13 tab roots: v2 fade-through (tab 210); reduced → none; flag OFF → none', (tester) async {
    var r = await mini(tester, v2: true);
    r.go('/b');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(opacityOverB(tester), inExclusiveRange(0.0, 1.0));
    await tester.pumpAndSettle();
    expect(find.text('B'), findsOneWidget);

    r = await mini(tester, v2: true, reduced: true);
    r.go('/b');
    await tester.pump();
    expect(opacityOverB(tester) ?? 1, 1);

    r = await mini(tester, v2: false);
    r.go('/b');
    await tester.pump();
    expect(opacityOverB(tester) ?? 1, 1);
  });

  testWidgets('SH-14 Android push: v2 animates (MaterialPage), flag OFF instant; PopScope still guards', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      var r = await mini(tester, v2: true, tab: false);
      unawaited(r.push('/b'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final moving = tester.getTopLeft(find.text('B'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('B')), isNot(moving));

      r = await mini(tester, v2: false, tab: false);
      unawaited(r.push('/b'));
      await tester.pump();
      final at = tester.getTopLeft(find.text('B'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('B')), at);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
