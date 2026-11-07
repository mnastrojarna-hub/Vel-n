// auth_sos_misc tests: pumps a screen inside a GoRouter app (the auth
// screens use BackButtonListener / context.go), v2 scope on / off, text
// scale and reduced motion like the app.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';

import 'v2_harness.dart' show v2TestTheme;

Future<GoRouter> pumpAsmRouted(
  WidgetTester tester,
  Widget screen, {
  bool v2 = true,
  String lang = 'cs',
  Size size = const Size(360, 780),
  double scale = 1.0,
  bool reduced = false,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => screen),
    for (final p in ['/login', '/register', '/reset-password', '/home', '/sos', '/sos/done', '/reservations', '/messages', '/ai-agent'])
      GoRoute(path: p, builder: (_, __) => Scaffold(body: Text('route:$p'))),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      rankTokensProvider.overrideWithValue(RankTokens.forLevel(3)),
      rankArcPctProvider.overrideWithValue(50),
      ...overrides,
    ],
    child: MaterialApp.router(
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
        enabled: v2,
        child: MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: reduced),
          child: child!,
        ),
      ),
    ),
  ));
  await tester.pump();
  return router;
}
