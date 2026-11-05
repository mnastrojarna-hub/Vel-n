// fix:statusbar r1 — the screens that lie under the status bar WITHOUT a v2
// region: root routes (navigation, document scanner, login / registration /
// password reset), old screens inside the v2 shell (e-shop, map picker),
// the non-opaque gallery and the v2 merge screen. Each declares its own
// brightness in the v2 look now (V-seam `mgV1StatusBar` in the old files;
// `MgStatusBar` in the v2 file). Every case pumps the screen inside a region
// of the OPPOSITE brightness — the pre-fix state, where the shell base / the
// page below / the last style decided — so the screen must win on its own.
// The old look (flag OFF) declares nothing, as before.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart' show FlutterMap;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/chrome/mg_page.dart';
import 'package:motogo_app/core/v2/chrome/mg_photo_hero.dart';
import 'package:motogo_app/core/v2/chrome/mg_status_bar.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/features/auth/login_screen.dart';
import 'package:motogo_app/features/auth/register_screen.dart';
import 'package:motogo_app/features/auth/reset_password_screen.dart';
import 'package:motogo_app/features/booking/widgets/map_picker.dart';
import 'package:motogo_app/features/catalog/widgets/fullscreen_gallery.dart';
import 'package:motogo_app/features/documents/docs_gate_provider.dart';
import 'package:motogo_app/features/documents/document_scanner_screen.dart';
import 'package:motogo_app/features/routes/route_navigation_screen.dart';
import 'package:motogo_app/features/routes/routes_model.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_merge_v2.dart';
import 'package:motogo_app/features/shop/product_detail_screen.dart';
import 'package:motogo_app/features/shop/shop_models.dart';
import 'package:motogo_app/features/shop/shop_provider.dart';
import 'package:motogo_app/features/shop/shop_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes_docs_scan.dart';
import 'support/fakes_rides_pause.dart' show tripOverrides;
import 'support/fakes_routes.dart';
import 'support/fakes_routes_http.dart';
import 'support/v2_harness.dart';

const _kTop = 44.0;
const _kSize = Size(360, 780);

/// The TOPMOST `SystemUiOverlayStyle` annotation at the status-bar centre of
/// the layer tree — what `RenderView._updateSystemChrome` sends to the OS.
SystemUiOverlayStyle? _topStyle(WidgetTester tester) {
  final view = tester.binding.renderViews.single;
  final dpr = tester.view.devicePixelRatio;
  final centre = Offset(view.size.width * dpr / 2, tester.view.padding.top / 2);
  return view.debugLayer?.find<SystemUiOverlayStyle>(centre);
}

/// Pumps [screen] as the root route of a real GoRouter on a 360×780 phone
/// with a 44 px status bar. [underDark] = the brightness of a region AROUND
/// it (the shell base / the page below before the seams); null = none.
Future<GoRouter> _pump(
  WidgetTester tester,
  Widget screen, {
  required bool? underDark,
  List<Override> overrides = const [],
  bool v2 = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = _kSize * 2;
  tester.view.devicePixelRatio = 2;
  tester.view.padding = FakeViewPadding(top: _kTop * 2);
  addTearDown(tester.view.reset);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => underDark == null ? screen : MgStatusBar(dark: underDark, child: screen)),
    GoRoute(path: '/login', builder: (_, __) => const SizedBox()),
    GoRoute(path: '/register', builder: (_, __) => const SizedBox()),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      rankTokensProvider.overrideWithValue(RankTokens.forLevel(3)),
      rankArcPctProvider.overrideWithValue(50),
      ...overrides,
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
        enabled: v2,
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

/// Unmounts the screen (dispose → wakelock off, streams closed).
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

/// wakelock_plus (navigation keeps the display on) answers over a pigeon
/// channel; without a platform it would throw an unhandled error.
void _mockWakelock(WidgetTester tester) {
  const codec = StandardMessageCodec();
  const base = 'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.';
  for (final m in ['toggle', 'isEnabled']) {
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      '$base$m',
      (_) async => codec.encodeMessage(<Object?>[m == 'toggle' ? null : false]),
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMessageHandler('$base$m', null));
  }
}

const _kNavRoute = RouteItem(
  id: 'c1',
  name: 'Vlastní vyjížďka',
  distanceKm: 12,
  durationMin: 20,
  difficulty: 'easy',
  waypoints: [LatLng(49.09, 16.61), LatLng(49.05, 16.64)],
  geometry: [LatLng(49.09, 16.61), LatLng(49.07, 16.62), LatLng(49.05, 16.64)],
  countries: ['CZ'],
);

const _kProduct = Product(
  id: 'p1',
  name: 'Tričko MotoGo24',
  price: 490,
  images: ['https://motogo24.cz/shop/tricko-1.png', 'https://motogo24.cz/shop/tricko-2.png'],
  sizes: ['M', 'L'],
  stockQuantity: 5,
);

List<Override> _shop([List<Product> products = const []]) => [
      productsProvider.overrideWith((ref) async => products),
    ];

List<Override> _docs() => [
      docsScreenStatusProvider.overrideWith((ref) async => st(gate())),
    ];

Widget _long() => const SizedBox(height: 3000);

Future<void> _jump(WidgetTester tester, double px) async {
  tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(px);
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    // Map tiles / photos answer 200 with a tiny PNG (no image error).
    HttpOverrides.global = RtFakeHttpOverrides();
  });

  testWidgets('Navigace trasy (root route: dark gradient panel over the map) → light icons', (tester) async {
    _mockWakelock(tester);
    await _pump(tester, const RouteNavigationScreen.custom(route: _kNavRoute), underDark: false, overrides: routesOverrides());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(_topStyle(tester), MgStatusBar.onDark);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('E-shop inside the shell (solid dark header under the status bar) → light icons', (tester) async {
    await _pump(tester, const ShopScreen(), underDark: false, overrides: _shop());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ShopScreen), findsOneWidget);
    expect(_topStyle(tester), MgStatusBar.onDark);
  });

  testWidgets('E-shop product detail (photo under the status bar) → light icons', (tester) async {
    await _pump(tester, const ProductDetailScreen(productId: 'p1'), underDark: false, overrides: _shop([_kProduct]));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(PageView), findsOneWidget, reason: 'the product is shown (not the loading state)');
    expect(_topStyle(tester), MgStatusBar.onDark);
  });

  testWidgets('Výběr adresy na mapě (pushed on the shell navigator: dark gradient top bar) → light icons',
      (tester) async {
    await _pump(tester, const MapPickerScreen(), underDark: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(_topStyle(tester), MgStatusBar.onDark);
    await _unmount(tester);
  });

  testWidgets('Galerie (non-opaque route) over the collapsed pinned bar → light icons; closed → dark again',
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
      underDark: true,
    );
    await _jump(tester, 500);
    expect(find.byKey(const ValueKey('mg-pinned-bar')), findsOneWidget);
    expect(_topStyle(tester), MgStatusBar.onLight);
    FullscreenGallery.open(tester.element(find.byType(MgPage)), images: const ['https://motogo24.cz/m/1.png']);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(FullscreenGallery), findsOneWidget);
    expect(_topStyle(tester), MgStatusBar.onDark);
    Navigator.of(tester.element(find.byType(FullscreenGallery))).pop();
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.byType(FullscreenGallery), findsNothing);
    expect(_topStyle(tester), MgStatusBar.onLight);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Skener dokladů (root route, dark) → light icons', (tester) async {
    await _pump(tester, const DocumentScannerScreen(scanMode: null), underDark: false, overrides: _docs());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(DocumentScannerScreen), findsOneWidget);
    expect(_topStyle(tester), MgStatusBar.onDark);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sloučení jízd (v2, pushed on the root navigator over a dark page) → dark icons', (tester) async {
    await _pump(tester, const Scaffold(body: Center(child: Text('MOJE'))), underDark: true, overrides: tripOverrides());
    expect(_topStyle(tester), MgStatusBar.onDark);
    unawaited(openRideMergeV2(tester.element(find.text('MOJE'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(RideMergeScreenV2), findsOneWidget);
    expect(_topStyle(tester), MgStatusBar.onLight);
    expect(tester.takeException(), isNull);
  });

  // Login + password reset: the dark gradient header lies under the status
  // bar → light icons; registration: SafeArea on the canvas → dark icons.
  for (final (name, screen, dark) in <(String, Widget, bool)>[
    ('Přihlášení', const LoginScreen(), true),
    ('Registrace', const RegisterScreen(), false),
    ('Obnova hesla', const ResetPasswordScreen(), true),
  ]) {
    testWidgets('$name (root route) declares its own top in v2 → ${dark ? 'light' : 'dark'} icons', (tester) async {
      await _pump(tester, screen, underDark: !dark);
      await tester.pump(const Duration(seconds: 3));
      expect(_topStyle(tester), MgStatusBar.styleFor(dark: dark));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('flag OFF: the old screens declare nothing (old look untouched)', (tester) async {
    _mockWakelock(tester);
    final cases = <(String, Widget, List<Override>)>[
      ('login', const LoginScreen(), const []),
      ('register', const RegisterScreen(), const []),
      ('reset', const ResetPasswordScreen(), const []),
      ('shop', const ShopScreen(), _shop()),
      ('product', const ProductDetailScreen(productId: 'p1'), _shop([_kProduct])),
      ('scanner', const DocumentScannerScreen(scanMode: null), _docs()),
      ('map picker', const MapPickerScreen(), const []),
      ('navigation', const RouteNavigationScreen.custom(route: _kNavRoute), routesOverrides()),
    ];
    for (final (name, screen, overrides) in cases) {
      await _pump(tester, screen, underDark: null, overrides: overrides, v2: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AnnotatedRegion<SystemUiOverlayStyle>), findsNothing, reason: name);
      expect(_topStyle(tester), isNull, reason: name);
      await _unmount(tester);
    }
  });
}
