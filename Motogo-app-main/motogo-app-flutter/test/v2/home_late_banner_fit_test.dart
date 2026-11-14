import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/banner_provider.dart';
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
import 'package:motogo_app/features/home/v2/home_funnel_v2.dart';
import 'package:motogo_app/features/home/v2/home_screen_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_test.dart' show homeCases;
import 'support/fakes_home.dart' show mockPathProvider;
import 'support/fakes_routes_http.dart';
import 'support/v2_harness.dart';

/// 5.0.1 LS1-01: the Velín banner is fetched asynchronously, so it can land
/// after the Home offer photo was sized from the room left on the first
/// screen. The photo must re-measure, so REZERVOVAT stays above the menu.
final _late = StateProvider<bool>((ref) => false);

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
  for (final lang in ['cs', 'nl', 'pl', 'uk']) {
  for (final size in const [Size(360, 640), Size(360, 780)]) {
  testWidgets('FS LS1-01: banner arriving after the Home offer keeps REZERVOVAT above the menu ($lang ${size.height})', (t) async {
    t.view.physicalSize = size * 2;
    t.view.devicePixelRatio = 2;
    t.view.padding = const FakeViewPadding(top: 48);
    addTearDown(t.view.reset);
    final router = GoRouter(initialLocation: '/', routes: [
      ShellRoute(builder: (_, __, child) => AppShellV2(child: child), routes: [
        GoRoute(path: '/', builder: (_, __) => const HomeScreenV2()),
      ]),
    ]);
    await t.pumpWidget(ProviderScope(
      overrides: [
        ...homeCases()['s0']!(),
        rankTokensProvider.overrideWithValue(RankTokens.forLevel(6)),
        rankArcPctProvider.overrideWithValue(50),
        appV2UiProvider.overrideWith((ref) => AppV2UiNotifier(fetch: () async => null, autoRefresh: false, initial: true)),
        paidAfterRestartProvider.overrideWith((ref) async => null),
        bannerProvider.overrideWith((ref) => AsyncData(ref.watch(_late)
            ? const BannerData(enabled: true, text: 'Zimní období zavřeno', bg: Color(0xFF0E2A1C), color: Color(0xFF74FB71))
            : null)),
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
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.noScaling, disableAnimations: true),
            child: child!,
          ),
        ),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
    double cta() => t.getRect(find.byWidgetPredicate((w) => w is MgCta && w.size == MgCtaSize.lg60).first).bottom;
    double photo() => t.getSize(find.descendant(of: find.byType(HomeFunnelV2), matching: find.byType(PageView))).height;
    final nav = t.getRect(find.byType(V2NavBar)).top;
    expect(cta(), lessThanOrEqualTo(nav));
    final before = photo();
    ProviderScope.containerOf(t.element(find.byType(HomeScreenV2))).read(_late.notifier).state = true;
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
    expect(cta(), lessThanOrEqualTo(t.getRect(find.byType(V2NavBar)).top));
    // The photo gives the room back (never grows when the header grows).
    expect(photo(), lessThanOrEqualTo(before));
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
  }}
}
