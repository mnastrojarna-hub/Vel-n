// THROWAWAY visual review of 5.0.3 (delete after use). Boots the REAL
// router + shell with fakes and writes PNGs to MG_V503_SHOTS.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/feature_flags.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/router.dart';
import 'package:motogo_app/core/safe_router_config.dart';
import 'package:motogo_app/core/supabase_client.dart';
import 'package:motogo_app/core/v2/flag/v2_gate.dart';
import 'package:motogo_app/core/v2/gestures/mg_zone_snap.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/shop/shop_models.dart';
import 'package:motogo_app/features/shop/shop_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'journey/journey_backend.dart';
import 'journey/journey_overrides.dart';
import 'journey/journey_states.dart';
import 'support/fakes_home.dart' show mockPathProvider;
import 'support/shot_images.dart' show installShotImages, warmShotImages;
import 'support/v2_harness.dart' show loadMontserrat, v2TestTheme;

final _out = Platform.environment['MG_V503_SHOTS'] ?? '/tmp/v503_shots';

String _img(String n) => '${MotoGoSupabase.url}/storage/v1/object/public/media/shop/$n.jpg';

final kShop = [
  Product(
      id: 'p1',
      name: 'Tričko MotoGo24',
      price: 590,
      color: 'bílé',
      material: '95 % polyester, 5 % elastan',
      description: 'Lehké funkční tričko s logem MotoGo24. Rychle schne, dobře dýchá a nemačká se. Hodí se pod bundu '
          'i na výlet. Praní na 30 °C, nesušit v sušičce.',
      images: [_img('tricko-1'), _img('tricko-2'), _img('tricko-3')],
      sizes: const ['S', 'M', 'L', 'XL', '2XL'],
      stockQuantity: 5),
  Product(
      id: 'p2',
      name: 'Letní motorkářské rukavice',
      price: 1290,
      description: 'Prodyšné rukavice s chrániči kloubů a dotykovým ukazováčkem.',
      images: [_img('rukavice')],
      sizes: const ['M', 'L', 'XL'],
      stockQuantity: 3),
  Product(id: 'p3', name: 'Truckerka MotoGo24', price: 490, images: [_img('ksiltovka')], stockQuantity: 0),
  Product(
      id: 'p4',
      name: 'Kukla reflexní',
      price: 186,
      description: 'Tenká kukla pod helmu s reflexním pruhem.',
      images: [_img('kukla')],
      stockQuantity: 9),
];

bool _iconsTried = false;
Future<void> _loadIcons() async {
  if (_iconsTried) return;
  _iconsTried = true;
  try {
    final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
    final f = File('${artifacts.path}/material_fonts/MaterialIcons-Regular.otf');
    if (!f.existsSync()) return;
    final loader = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(Uint8List.fromList(f.readAsBytesSync()).buffer)));
    await loader.load();
  } catch (_) {}
}

void _mockPlugins() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final ch in [
    'flutter.baseflow.com/permissions/methods', 'flutter.baseflow.com/geolocator', 'flutter.baseflow.com/geolocator_android',
    'plugins.flutter.io/url_launcher', 'plugins.flutter.io/url_launcher_android', 'dev.fluttercommunity.plus/connectivity',
    'dev.fluttercommunity.plus/package_info', 'dev.fluttercommunity.plus/share', 'flutter.io/videoPlayer',
    'plugins.it_nomads.com/flutter_secure_storage', 'plugins.flutter.io/local_auth', 'flutter.stripe/payments',
  ]) {
    m.setMockMethodCallHandler(MethodChannel(ch), (call) async => null);
  }
  m.setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/permissions/methods'), (call) async {
    switch (call.method) {
      case 'checkPermissionStatus':
      case 'checkServiceStatus':
        return 0;
      case 'requestPermissions':
        final list = call.arguments is List ? call.arguments as List : const [];
        return {for (final p in list) p: 0};
    }
    return false;
  });
  m.setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/geolocator'), (call) async => switch (call.method) {
        'isLocationServiceEnabled' => false,
        'checkPermission' || 'requestPermission' => 0,
        _ => null,
      });
}

class _App extends ConsumerWidget {
  final GlobalKey boundary;
  final bool motion;
  const _App(this.boundary, {this.motion = false});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return RepaintBoundary(
      key: boundary,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: v2TestTheme(),
        routerConfig: mgSafeRouterConfig(router),
        locale: const Locale('cs'),
        supportedLocales: supportedLocales,
        localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.noScaling, disableAnimations: !motion),
          child: MgV2Gate(router: router, child: child!),
        ),
      ),
    );
  }
}

class Rig {
  final WidgetTester t;
  final GlobalKey key;
  final String tag;
  Rig(this.t, this.key, this.tag);

  ProviderContainer get c => ProviderScope.containerOf(t.element(find.byType(_App)));
  GoRouter get router => c.read(routerProvider);

  Future<T> guard<T>(Future<T> Function() f) {
    final parent = Zone.current;
    final done = Completer<T>();
    runZoned(() {
      f().then(done.complete, onError: done.completeError);
    }, zoneSpecification: ZoneSpecification(handleUncaughtError: (self, p, zone, e, st) {
      if ('$e'.contains('markNeedsBuild() called during build')) return;
      parent.handleUncaughtError(e, st);
    }));
    return done.future;
  }

  Future<void> settle([int maxMs = 2500]) => guard(() async {
        await t.pump();
        await warmShotImages(t);
        var ms = 0;
        while (ms < maxMs) {
          await t.pump(const Duration(milliseconds: 100));
          ms += 100;
          if (ms >= 500 && !t.binding.hasScheduledFrame) break;
        }
      });

  Future<void> shot(String name) async {
    final ex = t.takeException();
    if (ex != null) stdout.writeln('EXCEPTION before $tag/$name: $ex');
    await guard(() => warmShotImages(t, rounds: 3));
    await t.runAsync(() async {
      final ro = key.currentContext?.findRenderObject();
      if (ro is! RenderRepaintBoundary) return;
      final ui.Image img = await ro.toImage(pixelRatio: 2.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      if (bytes == null) return;
      final f = File('$_out/${tag}_$name.png');
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(bytes.buffer.asUint8List());
    });
    stdout.writeln('SHOT $tag/$name @ ${router.routerDelegate.currentConfiguration.uri}');
  }

  Future<void> go(String p) async {
    router.go(p);
    await settle();
  }

  Future<void> push(String p) async {
    unawaited(router.push(p));
    await settle();
  }

  /// The page scroll of the topmost screen that has a snap zone.
  (ScrollPosition, MgSnapZone)? zone() {
    final f = find.byType(MgSnapZoneSliver, skipOffstage: false);
    if (f.evaluate().isEmpty) return null;
    final ro = t.renderObject<RenderMgSnapZone>(f.last);
    final s = Scrollable.of(f.evaluate().last);
    return (s.position, ro.zone);
  }

  Future<void> swipeUp(double dy) async {
    final size = t.view.physicalSize / t.view.devicePixelRatio;
    final g = await t.startGesture(Offset(size.width / 2, size.height * 0.7));
    for (var i = 0; i < 10; i++) {
      await g.moveBy(Offset(0, -dy / 10));
      await t.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await settle(1800);
  }
}

Future<Rig> boot(WidgetTester t,
    {Size size = const Size(360, 780), List<Product>? products, int cart = 2, double top = 28, bool motion = false}) async {
  await loadMontserrat();
  await _loadIcons();
  mockPathProvider();
  _mockPlugins();
  installShotImages();
  MgMotion.resetSession();
  final data = journeyData(JourneyState.ready);
  SharedPreferences.setMockInitialValues({'mg_intro_shown': true, 'mg_perms_shown': true});
  journeyBackendData = data;
  await initJourneyBackend();
  await t.runAsync(() => journeySetLoggedIn(true));
  t.view.physicalSize = size * 2;
  t.view.devicePixelRatio = 2;
  t.view.padding = FakeViewPadding(top: top * 2);
  t.view.viewPadding = FakeViewPadding(top: top * 2);
  addTearDown(t.view.reset);
  final key = GlobalKey();
  await t.pumpWidget(ProviderScope(overrides: [
    ...journeyOverrides(data),
    eshopVisibleProvider.overrideWith((ref) async => true),
    productsProvider.overrideWith((ref) async => products ?? kShop),
    cartProvider.overrideWith((ref) {
      final n = CartNotifier();
      for (var i = 0; i < cart; i++) {
        n.addItem('p1-L', 'Tričko MotoGo24 (L)', 590);
      }
      return n;
    }),
  ], child: _App(key, motion: motion)));
  final r = Rig(t, key, '${size.width.toInt()}x${size.height.toInt()}');
  await r.settle(3000);
  return r;
}

Future<void> end(Rig r) async {
  try {
    r.router.go('/');
    await r.settle(1500);
  } catch (_) {}
  await r.t.pumpWidget(const SizedBox());
  await r.t.pump(const Duration(seconds: 61));
}

void main() {
  for (final size in const [Size(360, 780), Size(320, 640)]) {
    final tag = '${size.width.toInt()}';
    testWidgets('v503 shots $tag: moje + shop + detail + motorky', (t) async {
      final r = await boot(t, size: size);
      // A) Trasy → Moje
      await r.go('/my-experiences');
      await r.settle(2500);
      await r.shot('a1_moje_summary');
      // B) shop from Profile
      await r.go('/profile');
      await r.push('/shop');
      await r.shot('b1_shop_top');
      var z = r.zone();
      if (z != null) {
        z.$1.jumpTo(z.$2.offsetOf(0) - 40);
        await r.settle(600);
        await r.swipeUp(40);
        await r.settle(1500);
        z = r.zone()!;
        stdout.writeln('zone start=${z.$2.start} extent=${z.$2.extent} px=${z.$1.pixels} active=${z.$2.active}');
        await r.shot('b2_shop_product1');
        await r.swipeUp(size.height * 0.62);
        z = r.zone()!;
        stdout.writeln('after swipe px=${z.$1.pixels} → item ${(z.$1.pixels - z.$2.start) / z.$2.extent}');
        await r.shot('b3_shop_product2');
        await r.swipeUp(size.height * 0.62);
        await r.shot('b4_shop_product3_soldout');
        // scroll back up a little: bars + arrow shown
        final g = await t.startGesture(Offset(size.width / 2, size.height * 0.4));
        for (var i = 0; i < 10; i++) {
          await g.moveBy(Offset(0, size.height * 0.045));
          await t.pump(const Duration(milliseconds: 16));
        }
        await g.up();
        await r.settle(1800);
        await r.shot('b5_shop_product2_bars_arrow');
      }
      // detail
      await r.push('/shop/p1');
      await r.settle(2000);
      await r.shot('c1_detail_top');
      final sc = find.byType(Scrollable).evaluate().map((e) => (e as StatefulElement).state as ScrollableState).where((s) => s.axisDirection == AxisDirection.down && s.position.maxScrollExtent > 0).toList();
      if (sc.isNotEmpty) {
        sc.last.position.jumpTo((sc.last.position.maxScrollExtent).clamp(0, 260));
        await r.settle(800);
        await r.shot('c2_detail_scrolled');
      }
      r.router.pop();
      await r.settle();
      await r.push('/shop/p3');
      await r.settle(2000);
      await r.shot('c3_detail_soldout');
      r.router.pop();
      await r.settle();
      // Motorky for comparison
      await r.go('/search');
      await r.settle(2500);
      final mz = r.zone();
      if (mz != null) {
        mz.$1.jumpTo(mz.$2.offsetOf(0) - 40);
        await r.settle(600);
        await r.swipeUp(40);
        await r.settle(1500);
        await r.shot('d1_motorky_card');
      }
      await end(r);
    });

    testWidgets('v503 shots $tag: shop empty + one product', (t) async {
      final r = await boot(t, size: size, products: const [], cart: 0);
      await r.go('/profile');
      await r.push('/shop');
      await r.shot('b6_shop_empty');
      final sc = find.byType(Scrollable).evaluate().map((e) => (e as StatefulElement).state as ScrollableState).where((s) => s.axisDirection == AxisDirection.down && s.position.maxScrollExtent > 0).toList();
      if (sc.isNotEmpty) {
        sc.last.position.jumpTo(sc.last.position.maxScrollExtent);
        await r.settle(800);
        await r.shot('b7_shop_empty_bottom');
      }
      await end(r);
    });
  }
}
