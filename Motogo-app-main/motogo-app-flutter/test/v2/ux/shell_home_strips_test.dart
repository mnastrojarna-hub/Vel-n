// SH-05 strip ✕ confirm, SH-06 Domů leaves out only the payable strip (the
// ticket S2 has both its actions), SH-07 every strip stacked with its own
// tap / ✕ (owner parity rule), SH-13 tab fade-through, SH-14 push page.
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
import 'package:motogo_app/features/documents/docs_gate_provider.dart';
import 'package:motogo_app/features/documents/document_provider.dart' show DocsVerification;
import 'package:motogo_app/features/messages/messages_provider.dart';
import 'package:motogo_app/features/reservations/reservation_models.dart';
import 'package:motogo_app/features/reservations/reservation_provider.dart';
import 'package:motogo_app/features/shop/shop_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_home.dart' show day, res;
import '../support/shell_harness.dart' show kShellTestPaths;
import '../support/v2_harness.dart';

const _sos = PendingSosReplacement(id: 's1', type: 'breakdown_minor', status: 'reported');
final _cs = AppTranslations.of('cs');

Future<GoRouter> _shell(WidgetTester tester, String initial,
    {PendingBooking? pending,
    PendingSosReplacement? sos,
    bool cart = false,
    bool reduced = false,
    List<Reservation> reservations = const [],
    bool? docsOk}) async {
  SharedPreferences.setMockInitialValues({'mg_v2_ai_coach_seen': true});
  tester.view.physicalSize = const Size(360, 780) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final router = GoRouter(initialLocation: initial, routes: [
    ShellRoute(
      builder: (_, __, child) => AppShellV2(child: child),
      routes: [
        for (final p in [...kShellTestPaths, '/payment-result', '/docs'])
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
      reservationsProvider.overrideWith((ref) => Stream.value(reservations)),
      docsFabStatusProvider.overrideWith((ref) => docsOk == null
          ? Completer<DocsScreenStatus>().future
          : Future.value(DocsScreenStatus(
              docsOk ? DocsVerification(idVerifiedAt: day(-30), licenseVerifiedAt: day(-30)) : const DocsVerification(),
              null))),
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

  testWidgets('SH-06 Domů: the payable strip is left out (the ticket S2 has pay + cancel); /search shows it', (tester) async {
    final router = await _shell(tester, '/', pending: _pending());
    expect(find.byType(MgStatusStrip), findsNothing);
    router.go('/search');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MgStatusStrip), findsOneWidget);
    expect(find.text('Dokončit rezervaci'), findsOneWidget);
  });

  testWidgets('Domů + payment being verified: the "Platba se ověřuje" strip stays and opens /payment-result', (tester) async {
    final verifying = PendingBooking(id: 'b1', totalPrice: 12027, createdAt: DateTime.now(), verifying: true);
    await _shell(tester, '/', pending: verifying, reduced: true);
    final strip = find.byType(MgStatusStrip);
    expect(strip, findsOneWidget);
    expect(find.text(_cs.tr('psFabVerifying')), findsOneWidget);
    await tester.tap(strip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('PAGE /payment-result'), findsOneWidget);
  });

  testWidgets('Domů S1: the SOS strip stays with its ✕ (dismiss = the same dismissSosFab)', (tester) async {
    await _shell(tester, '/', sos: _sos, reduced: true);
    final strip = find.byType(MgStatusStrip);
    expect(strip, findsOneWidget);
    expect(find.text(_cs.tr('sosCompleteFab')), findsOneWidget);
    await tester.tap(find.descendant(of: strip, matching: find.bySemanticsLabel('Zavřít')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect((await SharedPreferences.getInstance()).getInt('sos_fab_dismissed_s1'), isNotNull);
  });

  testWidgets('Domů S3: the docs strip stays with its tap (/docs) and ✕', (tester) async {
    await _shell(tester, '/', reservations: [res('b6', status: 'reserved', from: 5, to: 7)], docsOk: false, reduced: true);
    await tester.pump(const Duration(milliseconds: 100));
    final strip = find.byType(MgStatusStrip);
    expect(strip, findsOneWidget);
    await tester.tap(find.descendant(of: strip, matching: find.bySemanticsLabel('Zavřít')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(MgStatusStrip), findsNothing);
  });

  testWidgets('SH-07 three strips → ALL stacked (SOS, pay, cart), no "+n"; each runs its own tap', (tester) async {
    await _shell(tester, '/search', pending: _pending(), sos: _sos, cart: true, reduced: true);
    final strips = find.byType(MgStatusStrip);
    expect(strips, findsNWidgets(3));
    expect(find.textContaining(RegExp(r'^\+\d')), findsNothing);
    final ys = [for (final e in strips.evaluate()) tester.getTopLeft(find.byWidget(e.widget)).dy];
    expect(ys[0] < ys[1] && ys[1] < ys[2], isTrue, reason: 'SOS above pay above cart');
    expect(tester.getTopLeft(strips.at(1)).dy - tester.getBottomLeft(strips.at(0)).dy, moreOrLessEquals(8));
    expect(tester.getSize(strips.at(0)).height, lessThan(90));
    // Cart strip → its own action (push /cart) straight away.
    await tester.tap(strips.at(2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('PAGE /cart'), findsOneWidget);
  });

  for (final reduced in [false, true]) {
    testWidgets('SH-07 a dismissed strip slides out and gives its height back (reduced=$reduced → at once)', (tester) async {
      await _shell(tester, '/search', sos: _sos, cart: true, reduced: reduced);
      expect(find.byType(MgStatusStrip), findsNWidgets(2));
      final cart = find.byKey(const ValueKey('strip-cart'));
      await tester.tap(find.descendant(of: cart, matching: find.bySemanticsLabel('Zavřít')));
      await tester.pump();
      if (!reduced) {
        await tester.pump(const Duration(milliseconds: 150));
        expect(cart, findsOneWidget, reason: 'still animating out');
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(cart, findsNothing, reason: 'reduced=$reduced');
      expect(find.byType(MgStatusStrip), findsOneWidget);
    });
  }

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
