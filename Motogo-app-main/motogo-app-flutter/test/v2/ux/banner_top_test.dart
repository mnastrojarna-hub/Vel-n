// 5.0.1 (owner: "chybí mi nahoře takový ten banner, který zadává ve Velíně
// … jak na webu"): in the REAL v2 shell the Velín banner is the FIRST thing
// at the top of Domů and Motorky too — the shell's one-line band right
// under the status bar, ending with a hairline in the banner text colour,
// then the dark page header (no banner line of its own). Nothing covers
// it: a tap on it opens the whole text. Without a banner the header starts
// at the very top as before. Live values: support/fake_banner.dart.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/feature_flags.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/core/pending_sos_fab_provider.dart';
import 'package:motogo_app/core/v2/chrome/mg_top_banner.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/core/v2/shell/app_shell_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_header_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';
import 'package:motogo_app/features/documents/docs_gate_provider.dart';
import 'package:motogo_app/features/home/v2/home_header_v2.dart';
import 'package:motogo_app/features/home/v2/home_screen_v2.dart';
import 'package:motogo_app/features/messages/messages_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/home_test.dart' show homeCases;
import '../support/fake_banner.dart';
import '../support/fakes_catalog.dart' show catalogOverrides, registerCatalogStrings;
import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_routes_http.dart';
import '../support/v2_harness.dart';

final _cs = AppTranslations.of('cs');

Future<void> _pump(WidgetTester t, String route, Size size, {required bool banner}) async {
  t.view.physicalSize = size * 2;
  t.view.devicePixelRatio = 2;
  t.view.padding = const FakeViewPadding(top: 48);
  addTearDown(t.view.reset);
  final router = GoRouter(initialLocation: route, routes: [
    ShellRoute(builder: (_, __, child) => AppShellV2(child: child), routes: [
      GoRoute(path: '/', builder: (_, __) => const HomeScreenV2()),
      GoRoute(path: '/search', builder: (_, __) => const MotorkyScreenV2()),
    ]),
  ]);
  addTearDown(router.dispose);
  await t.pumpWidget(ProviderScope(
    overrides: [
      ...(route == '/'
          ? homeCases()['s0']!()
          : [
              ...catalogOverrides(),
              pendingBookingFabProvider.overrideWith((ref) => Stream.value(null)),
              pendingSosFabProvider.overrideWith((ref) => Stream.value(null)),
              docsFabStatusProvider.overrideWith((ref) => Completer<DocsScreenStatus>().future),
              adminUnreadCountProvider.overrideWithValue(0),
            ]),
      rankTokensProvider.overrideWithValue(RankTokens.forLevel(6)),
      rankArcPctProvider.overrideWithValue(50),
      appV2UiProvider.overrideWith((ref) => AppV2UiNotifier(fetch: () async => null, autoRefresh: false, initial: true)),
      paidAfterRestartProvider.overrideWith((ref) async => null),
      liveBannerOverride(on: banner),
    ],
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
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
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.noScaling, disableAnimations: true),
          child: child!,
        ),
      ),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _end(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerCatalogStrings();
    mockPathProvider();
    HttpOverrides.global = RtFakeHttpOverrides();
  });
  setUp(() {
    MgMotion.resetSession();
    SharedPreferences.setMockInitialValues({});
  });

  for (final (route, header) in [('/', HomeHeaderV2), ('/search', MotorkyHeaderV2)]) {
    for (final size in const [Size(360, 780), Size(320, 640)]) {
      final tag = '$route ${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('Velín banner = the topmost band, header right under it · $tag', (t) async {
        await _pump(t, route, size, banner: true);
        final band = find.byType(MgTopBanner);
        expect(band, findsOneWidget, reason: 'one banner: the shell band, none in the header');
        expect(t.widget<MgTopBanner>(band).band, isTrue);
        expect(find.descendant(of: find.byType(header), matching: find.byType(MgTopBanner)), findsNothing);
        final r = t.getRect(band);
        // Under the status bar (24 dp): the band paints it, the line sits below it.
        expect(r.top, 0);
        expect(r.height, 24 + MgTopBanner.height + MgTopBanner.hairline);
        // The band keeps the Velín colours; the hairline is the text colour.
        final fill = find.descendant(of: band, matching: find.byWidgetPredicate((w) => w is Container && w.color == kLiveBanner.bg));
        expect(fill, findsOneWidget);
        expect(t.getRect(fill), r);
        final texts = t.widgetList<Text>(find.descendant(of: band, matching: find.byType(Text)));
        expect(texts, isNotEmpty);
        expect(texts.every((x) => x.style?.color == kLiveBanner.color), isTrue);
        final line = find.byKey(const ValueKey('mg-top-banner-hairline'));
        expect(t.widget<ColoredBox>(line).color, kLiveBanner.color);
        expect(t.getRect(line).bottom, r.bottom);
        expect(t.getRect(line).width, size.width, reason: 'full width');
        // The dark page header starts right under the hairline.
        expect(t.getRect(find.byType(header)).top, moreOrLessEquals(r.bottom));
        // Nothing covers the line: a tap opens the whole text.
        await t.tapAt(Offset(size.width / 2, 24 + MgTopBanner.height / 2));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text(_cs.tr('v2BannerTitle')), findsOneWidget);
        expect(find.text(kLiveBannerText), findsWidgets);
        expect(t.takeException(), isNull);
        await _end(t);
      });

      testWidgets('no banner → no band, the header starts at the top as before · $tag', (t) async {
        await _pump(t, route, size, banner: false);
        expect(find.byType(MgTopBanner), findsNothing);
        expect(t.getRect(find.byType(header)).top, 0);
        expect(t.takeException(), isNull);
        await _end(t);
      });
    }
  }
}
