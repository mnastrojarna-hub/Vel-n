// pay_shop package tests: pumps a screen inside a GoRouter app (the
// payment / shop screens use BackButtonListener, context.go / push) with
// the v2 scope, Montserrat, rank overrides and optional reduced motion.
// Destination routes are plain pages that show their path, so a test can
// assert where a button went.
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
import 'package:shared_preferences/shared_preferences.dart';

import 'v2_harness.dart' show loadMontserrat, v2TestTheme;

class _FixedLocale extends LocaleNotifier {
  _FixedLocale(String lang) {
    state = Locale(lang);
  }
}

const kPsDestinations = ['/reservations', '/cart', '/voucher', '/checkout', '/shop', '/profile', '/docs', '/x'];

/// Pumps [screen] at '/' of a GoRouter; returns the router.
Future<GoRouter> pumpPs(
  WidgetTester tester,
  Widget screen, {
  String lang = 'cs',
  Size size = const Size(360, 780),
  List<Override> overrides = const [],
  bool v2 = true,
  bool reducedMotion = true,
  double textScale = 1.0,
  EdgeInsets viewInsets = EdgeInsets.zero,
}) async {
  await loadMontserrat();
  MgMotion.resetSession();
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final router = GoRouter(routes: [
    // Like the app shell: the shell Scaffold does not resize for the keyboard.
    GoRoute(path: '/', builder: (_, __) => Scaffold(resizeToAvoidBottomInset: false, body: screen)),
    GoRoute(path: '/shop/:id', builder: (_, s) => Scaffold(body: Text('route:/shop/${s.pathParameters['id']}'))),
    for (final p in kPsDestinations) GoRoute(path: p, builder: (_, __) => Scaffold(body: Text('route:$p'))),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    // A fresh container per pump (overrides of a kept scope would not apply).
    key: UniqueKey(),
    overrides: [
      localeProvider.overrideWith((ref) => _FixedLocale(lang)),
      rankTokensProvider.overrideWithValue(RankTokens.forLevel(3)),
      rankArcPctProvider.overrideWithValue(50),
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
      builder: (context, c) => MgV2Scope(
        enabled: v2,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reducedMotion,
            viewInsets: viewInsets,
          ),
          child: c!,
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return router;
}

/// Leaves '/' so screens that write providers one frame after dispose do
/// it while the ProviderScope still lives.
Future<void> psLeaveRoute(WidgetTester tester, GoRouter router) async {
  router.go('/x');
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(milliseconds: 50));
}

/// The current path of [router].
String psPath(GoRouter router) => router.routerDelegate.currentConfiguration.uri.path;
