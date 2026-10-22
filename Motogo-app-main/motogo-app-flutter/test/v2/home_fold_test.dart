// Home without a booking = booking funnel (DESIGN_V22 §2.4 Main #1 / #4):
// in the REAL v2 shell (nav, AI button, strips) at 360×780 the funnel's
// REZERVOVAT · price CTA ends above the bottom nav in all 8 languages —
// compact header (one-line greeting / banner / note) + 150 px photo on
// phones under 800 dp. Text scale = the app's (main.dart forces no scaling).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/feature_flags.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/core/v2/chrome/v2_nav_bar.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/core/v2/shell/app_shell_v2.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/home/v2/home_screen_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_test.dart' show homeCases;
import 'support/fakes_home.dart' show mockPathProvider;
import 'support/fakes_routes_http.dart';
import 'support/v2_harness.dart';

GoRouter _router() => GoRouter(initialLocation: '/', routes: [
      ShellRoute(builder: (_, __, child) => AppShellV2(child: child), routes: [
        GoRoute(path: '/', builder: (_, __) => const HomeScreenV2()),
      ]),
    ]);

void main() {
  setUpAll(() async {
    await loadMontserrat();
    mockPathProvider();
    HttpOverrides.global = RtFakeHttpOverrides();
  });
  setUp(() {
    MgMotion.resetSession();
    SharedPreferences.setMockInitialValues({});
  });

  for (final lang in kV2Langs) {
    testWidgets('home funnel CTA above the nav · $lang 360x780', (tester) async {
      tester.view.physicalSize = const Size(360, 780) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ...homeCases()['s0']!(),
          rankTokensProvider.overrideWithValue(RankTokens.forLevel(6)),
          rankArcPctProvider.overrideWithValue(50),
          appV2UiProvider.overrideWith((ref) => AppV2UiNotifier(fetch: () async => null, autoRefresh: false, initial: true)),
          paidAfterRestartProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: _router(),
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
              data: MediaQuery.of(c).copyWith(textScaler: TextScaler.noScaling, disableAnimations: true),
              child: child!,
            ),
          ),
        ),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      final cta = find.byWidgetPredicate((w) => w is MgCta && w.size == MgCtaSize.lg60);
      expect(cta, findsWidgets, reason: 'funnel CTA ($lang)');
      final ctaBottom = tester.getRect(cta.first).bottom;
      final navTop = tester.getRect(find.byType(V2NavBar)).top;
      expect(ctaBottom, lessThanOrEqualTo(navTop), reason: 'REZERVOVAT under the nav in $lang');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
