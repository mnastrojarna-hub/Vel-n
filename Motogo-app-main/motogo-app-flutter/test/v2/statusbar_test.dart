// fix:statusbar — main.dart sets ONE global status-bar style (white clock /
// battery for the old dark tops); every v2 surface under the status bar now
// declares its own brightness through `MgStatusBar` (an
// AnnotatedRegion<SystemUiOverlayStyle>): dark icons over light tops
// (canvas, white app bar, the collapsed pinned bar), light icons over dark
// ones (rank / photo heroes, dark app bar, banner band, night screens).
// Flutter takes the TOPMOST region under the status-bar centre, so the
// checks below read the layer tree exactly as RenderView does.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/banner_provider.dart';
import 'package:motogo_app/core/feature_flags.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/core/pending_sos_fab_provider.dart';
import 'package:motogo_app/core/v2/chrome/mg_app_bar.dart';
import 'package:motogo_app/core/v2/chrome/mg_page.dart';
import 'package:motogo_app/core/v2/chrome/mg_photo_hero.dart';
import 'package:motogo_app/core/v2/chrome/mg_status_bar.dart';
import 'package:motogo_app/core/v2/chrome/mg_top_banner.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/rank/rank_hero.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/core/v2/shell/app_shell_v2.dart';
import 'package:motogo_app/core/v2/states/mg_state_screen.dart';
import 'package:motogo_app/core/v2/tokens/mg_colors.dart';
import 'package:motogo_app/features/documents/docs_gate_provider.dart';
import 'package:motogo_app/features/loyalty/v2/loyalty_screen_v2.dart';
import 'package:motogo_app/features/messages/messages_provider.dart';
import 'package:motogo_app/features/reservations/reservation_provider.dart';
import 'package:motogo_app/features/routes/v2/builder_parts_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes_home.dart' show loyaltyAt;
import 'support/fakes_profile.dart';
import 'support/fakes_profile_sub.dart';
import 'support/profile_harness.dart';
import 'support/v2_harness.dart';

/// Status-bar height (logical px) of the fake phone.
const _kTop = 44.0;
const _kSize = Size(360, 780);

/// What Flutter sends to the OS for the status bar this frame: the TOPMOST
/// `SystemUiOverlayStyle` annotation at the status-bar centre of the layer
/// tree (`RenderView._updateSystemChrome` reads the same point, in physical
/// pixels). null = no v2 surface declared anything (the pre-fix state).
SystemUiOverlayStyle? _topStyle(WidgetTester tester) {
  final view = tester.binding.renderViews.single;
  final dpr = tester.view.devicePixelRatio;
  final centre = Offset(view.size.width * dpr / 2, tester.view.padding.top / 2);
  return view.debugLayer?.find<SystemUiOverlayStyle>(centre);
}

Brightness? _icons(WidgetTester tester) => _topStyle(tester)?.statusBarIconBrightness;

/// Pumps [child] on a 360×780 phone with a 44 px status bar.
Future<void> _pump(WidgetTester tester, Widget child,
    {List<Override> overrides = const [], bool scaffold = false, bool v2 = true}) async {
  tester.view.padding = FakeViewPadding(top: _kTop * 2);
  await pumpV2(tester, child, size: _kSize, overrides: overrides, reducedMotion: true, scaffold: scaffold, v2: v2);
  await tester.pump();
  await tester.pump();
}

Widget _long() => const SizedBox(height: 3000);

ScrollableState _scroll(WidgetTester tester) => tester.state<ScrollableState>(find.byType(Scrollable).first);

Future<void> _jump(WidgetTester tester, double px) async {
  _scroll(tester).position.jumpTo(px);
  await tester.pump();
  await tester.pump();
}

GoRouter _shellRouter(String initial) => GoRouter(
      initialLocation: initial,
      routes: [
        ShellRoute(
          builder: (_, __, child) => AppShellV2(child: child),
          routes: [
            // An old-look screen inside the v2 shell (SOS, platba): no region of its own.
            GoRoute(path: '/sos', builder: (_, __) => const Scaffold(body: SafeArea(child: Text('SOS')))),
            for (final p in ['/', '/search', '/reservations', '/routes', '/profile'])
              GoRoute(path: p, builder: (_, __) => MgPage(tabIndex: 0, sections: [Text('PAGE $p'), _long()])),
            GoRoute(
              path: '/moto/:id',
              builder: (_, s) => MgPage(
                header: MgAppBar(title: 'MOTO ${s.pathParameters['id']}', onBack: () {}),
                sections: [_long()],
              ),
            ),
          ],
        ),
      ],
    );

/// AppShellV2 in a real GoRouter (same overrides as shell_test).
Future<GoRouter> _pumpShell(WidgetTester tester, String initial, {bool banner = false}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = _kSize * 2;
  tester.view.devicePixelRatio = 2;
  tester.view.padding = FakeViewPadding(top: _kTop * 2);
  addTearDown(tester.view.reset);
  final router = _shellRouter(initial);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      rankTokensProvider.overrideWithValue(RankTokens.forLevel(10)),
      rankArcPctProvider.overrideWithValue(50),
      appV2UiProvider.overrideWith((ref) => AppV2UiNotifier(fetch: () async => null, autoRefresh: false, initial: true)),
      bannerProvider.overrideWithValue(AsyncData(banner
          ? const BannerData(enabled: true, text: 'Sezóna 2027 začíná', bg: Colors.black, color: Colors.white)
          : null)),
      pendingBookingFabProvider.overrideWith((ref) => Stream.value(null)),
      pendingSosFabProvider.overrideWith((ref) => Stream.value(null)),
      paidAfterRestartProvider.overrideWith((ref) async => null),
      reservationsProvider.overrideWith((ref) => Stream.value(const [])),
      docsFabStatusProvider.overrideWith((ref) => Completer<DocsScreenStatus>().future),
      adminUnreadCountProvider.overrideWithValue(0),
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
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.noScaling, disableAnimations: true),
          child: child!,
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return router;
}

void main() {
  setUpAll(loadMontserrat);

  test('MgStatusBar: both platform fields, transparent bar, nav bar untouched', () {
    for (final s in [MgStatusBar.onDark, MgStatusBar.onLight]) {
      expect(s.statusBarColor, Colors.transparent);
      expect(s.systemStatusBarContrastEnforced, isFalse);
      // Android icons vs iOS background brightness always disagree by design.
      expect(s.statusBarIconBrightness, isNot(s.statusBarBrightness));
      expect(s.systemNavigationBarColor, isNull);
      expect(s.systemNavigationBarIconBrightness, isNull);
      expect(s.systemNavigationBarDividerColor, isNull);
      expect(s.systemNavigationBarContrastEnforced, isNull);
    }
    expect(MgStatusBar.onDark.statusBarIconBrightness, Brightness.light);
    expect(MgStatusBar.onDark.statusBarBrightness, Brightness.dark);
    expect(MgStatusBar.onLight.statusBarIconBrightness, Brightness.dark);
    expect(MgStatusBar.onLight.statusBarBrightness, Brightness.light);
    expect(MgStatusBar.styleFor(dark: true), MgStatusBar.onDark);
    expect(MgStatusBar.styleFor(dark: false), MgStatusBar.onLight);
    for (final c in [MgColors.canvas, MgColors.surface, MgColors.well, MgColors.canvas.withValues(alpha: 0.94)]) {
      expect(MgStatusBar.isDark(c), isFalse, reason: '$c');
    }
    for (final c in [MgColors.night, MgColors.panel, MgColors.ink, MgColors.glow]) {
      expect(MgStatusBar.isDark(c), isTrue, reason: '$c');
    }
  });

  testWidgets('light-top MgPage (no header) → dark icons; reaches SystemChrome, nav bar fields null', (tester) async {
    await _pump(tester, MgPage(sections: [_long()]));
    expect(find.byType(AnnotatedRegion<SystemUiOverlayStyle>), findsWidgets);
    expect(_topStyle(tester), MgStatusBar.onLight);
    // The framework forwarded it (microtask after the frame).
    final sent = SystemChrome.latestStyle;
    expect(sent, isNotNull);
    expect(sent!.statusBarIconBrightness, Brightness.dark);
    expect(sent.statusBarBrightness, Brightness.light);
    expect(sent.statusBarColor, Colors.transparent);
    expect(sent.systemNavigationBarColor, isNull);
    expect(sent.systemNavigationBarIconBrightness, isNull);
  });

  testWidgets('MgPage with a white background → dark icons', (tester) async {
    await _pump(tester, MgPage(background: MgColors.surface, sections: [_long()]));
    expect(_topStyle(tester), MgStatusBar.onLight);
  });

  testWidgets('MgPage: dark MgAppBar → light icons; light MgAppBar → dark icons', (tester) async {
    await _pump(tester, MgPage(header: MgAppBar(title: 'Doklady', onBack: () {}), sections: [_long()]));
    expect(_topStyle(tester), MgStatusBar.onDark);
    await _pump(tester, MgPage(header: MgAppBar(title: 'Doklady', onBack: () {}, light: true), sections: [_long()]));
    expect(_topStyle(tester), MgStatusBar.onLight);
  });

  testWidgets('MgPage + rank hero + pinned back: hero → light icons, collapsed bar → dark, back up → light',
      (tester) async {
    final ctrl = ScrollController();
    addTearDown(ctrl.dispose);
    await _pump(
      tester,
      MgPage(
        controller: ctrl,
        header: const MgRankHero(ambient: false, child: SizedBox(height: 160)),
        pinnedBack: () {},
        pinnedTitle: 'Profil',
        sections: [_long()],
      ),
    );
    expect(_icons(tester), Brightness.light);
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.light);
    await _jump(tester, 600);
    expect(find.byKey(const ValueKey('mg-pinned-bar')), findsOneWidget);
    expect(_topStyle(tester), MgStatusBar.onLight);
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.dark);
    await _jump(tester, 0);
    expect(find.byKey(const ValueKey('mg-pinned-bar')), findsNothing);
    expect(_topStyle(tester), MgStatusBar.onDark);
  });

  testWidgets('MgPage, photo hero as first section (detail): hero → light, pinned DISC keeps it, bar → dark',
      (tester) async {
    final ctrl = ScrollController();
    addTearDown(ctrl.dispose);
    await _pump(
      tester,
      MgPage(
        controller: ctrl,
        overlapHero: false,
        pinnedBack: () {},
        pinnedTitle: 'Honda CB500X',
        sections: [
          MgPhotoHero(image: const ColoredBox(color: Colors.white), kenBurns: false, onBack: () {}, title: 'Honda'),
          _long(),
        ],
      ),
    );
    expect(_topStyle(tester), MgStatusBar.onDark);
    // 320 + 44 px hero: at 150 px the photo still lies under the status bar
    // → the bare photo disc, light icons stay.
    await _jump(tester, 150);
    expect(find.byKey(const ValueKey('mg-pinned-disc')), findsOneWidget);
    expect(_topStyle(tester), MgStatusBar.onDark);
    // Hero gone → the light collapsed bar is the surface → dark icons.
    await _jump(tester, 500);
    expect(find.byKey(const ValueKey('mg-pinned-bar')), findsOneWidget);
    expect(_topStyle(tester), MgStatusBar.onLight);
  });

  testWidgets('MgPage without pinned back: scrolled past a dark header → canvas → dark icons', (tester) async {
    await _pump(tester, MgPage(header: MgAppBar(title: 'Zprávy', onBack: () {}), sections: [_long()]));
    expect(_topStyle(tester), MgStatusBar.onDark);
    await _jump(tester, 800);
    expect(_topStyle(tester), MgStatusBar.onLight);
  });

  testWidgets('Profil tab root (hub): rank hero → light icons; scrolled → canvas → dark icons', (tester) async {
    await _pump(tester, const PfHubHarness(), overrides: profileOverrides());
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MgRankHero), findsOneWidget);
    expect(_topStyle(tester), MgStatusBar.onDark);
    final s = _scroll(tester);
    await _jump(tester, s.position.maxScrollExtent);
    expect(_topStyle(tester), MgStatusBar.onLight);
    expect(tester.takeException(), isNull);
  });

  for (final tone in [MgTone.ok, MgTone.pending]) {
    testWidgets('MgStateScreen $tone: dark hero → light icons; scrolled away → dark icons', (tester) async {
      await _pump(
        tester,
        MgStateScreen(
          tone: tone,
          title: 'Zaplaceno',
          why: 'Potvrzení přijde e-mailem.',
          steps: List.generate(20, (i) => 'Krok ${i + 1}'),
          primary: MgStateAction('Pokračovat', () {}),
          onClose: () {},
        ),
      );
      expect(_topStyle(tester), MgStatusBar.onDark);
      await _jump(tester, _scroll(tester).position.maxScrollExtent);
      expect(_topStyle(tester), MgStatusBar.onLight);
    });
  }

  for (final tone in [MgTone.warn, MgTone.err, MgTone.info]) {
    testWidgets('MgStateScreen $tone: canvas → dark icons', (tester) async {
      await _pump(
        tester,
        MgStateScreen(tone: tone, title: 'Platba se nezdařila', why: 'Banka ji zamítla.', onClose: () {}),
      );
      expect(_topStyle(tester), MgStatusBar.onLight);
    });
  }

  testWidgets('banner band (night) → light icons; builder top bar (scrim) → light icons', (tester) async {
    await _pump(
      tester,
      const Column(children: [MgTopBanner(text: 'Sezóna 2027 začíná', band: true), Expanded(child: SizedBox())]),
    );
    expect(_topStyle(tester), MgStatusBar.onDark);
    await _pump(
      tester,
      Column(children: [BuilderTopBarV2(title: 'Trasa', onBack: () {}, computing: false), const Expanded(child: SizedBox())]),
    );
    expect(_topStyle(tester), MgStatusBar.onDark);
  });

  testWidgets('Věrnostní ranky (night screen) → light icons', (tester) async {
    await _pump(tester, const LoyaltyScreenV2(), overrides: loyaltyOverrides(status: loyaltyAt(3)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_topStyle(tester), MgStatusBar.onDark);
  });

  testWidgets('AppShellV2: light tab root → dark icons; pushed dark page wins; pop restores', (tester) async {
    final router = await _pumpShell(tester, '/');
    expect(find.text('PAGE /'), findsOneWidget);
    expect(_topStyle(tester), MgStatusBar.onLight);
    router.push('/moto/7');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('MOTO 7'), findsOneWidget);
    expect(_topStyle(tester), MgStatusBar.onDark);
    router.pop();
    // The popped route stays in the tree for its reverse transition.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(find.text('MOTO 7'), findsNothing);
    expect(_topStyle(tester), MgStatusBar.onLight);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppShellV2: Velín banner band over a light tab → light icons (band is the surface)', (tester) async {
    await _pumpShell(tester, '/reservations', banner: true);
    expect(find.byType(MgTopBanner), findsOneWidget);
    expect(_topStyle(tester), MgStatusBar.onDark);
  });

  testWidgets('AppShellV2: a v1 screen inside the shell (no region of its own) gets the shell canvas → dark icons',
      (tester) async {
    await _pumpShell(tester, '/sos');
    expect(find.text('SOS'), findsOneWidget);
    expect(find.byType(MgPage), findsNothing);
    expect(_topStyle(tester), MgStatusBar.onLight);
  });

  testWidgets('flag OFF: the old look declares nothing (untouched)', (tester) async {
    await _pump(
      tester,
      V2Switch(v1: const Scaffold(body: SafeArea(child: Text('OLD'))), v2: MgPage(sections: [_long()])),
      v2: false,
    );
    expect(find.text('OLD'), findsOneWidget);
    expect(find.byType(AnnotatedRegion<SystemUiOverlayStyle>), findsNothing);
    expect(_topStyle(tester), isNull);
  });
}
