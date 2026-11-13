// Journey rig — boots the REAL app router (lib/core/router.dart →
// routerProvider: real redirects, real routes, real v2 shell through
// V2Switch, MgV2Gate) with the v2 flag ON, Czech, 360×780, text scale 1.0,
// reduced motion, every backend faked (journey_overrides.dart,
// journey_backend.dart). Steps / screenshots: journey_steps.dart.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/router.dart';
import 'package:motogo_app/core/safe_router_config.dart';
import 'package:motogo_app/core/v2/flag/v2_gate.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/widgets/mg_back.dart' show mgCurrentLocation;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_home.dart' show mockPathProvider;
import '../support/v2_harness.dart' show loadMontserrat, v2TestTheme;
import 'journey_backend.dart';
import 'journey_overrides.dart';
import 'journey_states.dart';

const kJourneySize = Size(360, 780);

bool _iconsTried = false;

/// Material icons from the Flutter SDK cache (the test font draws boxes).
Future<void> _loadIcons() async {
  if (_iconsTried) return;
  _iconsTried = true;
  try {
    // …/bin/cache/artifacts/engine/<host>/flutter_tester → …/bin/cache/artifacts
    final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
    final f = File('${artifacts.path}/material_fonts/MaterialIcons-Regular.otf');
    if (!f.existsSync()) return;
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.view(Uint8List.fromList(f.readAsBytesSync()).buffer)));
    await loader.load();
  } catch (_) {}
}

/// Plugin channels the app touches at runtime → harmless answers, so a
/// missing plugin never throws in the middle of a journey.
void _mockPlugins() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final ch in [
    'flutter.baseflow.com/permissions/methods',
    'flutter.baseflow.com/geolocator',
    'flutter.baseflow.com/geolocator_android',
    'flutter.baseflow.com/geolocator_apple',
    'plugins.flutter.io/url_launcher',
    'plugins.flutter.io/url_launcher_android',
    'dev.fluttercommunity.plus/connectivity',
    'dev.fluttercommunity.plus/package_info',
    'dev.fluttercommunity.plus/share',
    'flutter.io/videoPlayer',
    'plugins.it_nomads.com/flutter_secure_storage',
    'plugins.flutter.io/local_auth',
    'flutter.stripe/payments',
  ]) {
    m.setMockMethodCallHandler(MethodChannel(ch), (call) async => null);
  }
  // Typed answers where a plugin casts the result: permissions "denied"
  // (as on a fresh install), location services off.
  m.setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/permissions/methods'), (call) async {
    switch (call.method) {
      case 'checkPermissionStatus':
      case 'checkServiceStatus':
        return 0;
      case 'requestPermissions':
        final list = call.arguments is List ? call.arguments as List : const [];
        return {for (final p in list) p: 0};
      case 'shouldShowRequestPermissionRationale':
      case 'openAppSettings':
        return false;
    }
    return null;
  });
  for (final ch in ['flutter.baseflow.com/geolocator', 'flutter.baseflow.com/geolocator_android', 'flutter.baseflow.com/geolocator_apple']) {
    m.setMockMethodCallHandler(MethodChannel(ch), (call) async => switch (call.method) {
          'isLocationServiceEnabled' => false,
          'checkPermission' || 'requestPermission' => 0,
          _ => null,
        });
  }
}

class JourneyRig {
  final WidgetTester tester;
  final JourneyData data;
  final GlobalKey boundary;
  final SemanticsHandle _semantics;
  JourneyRig._(this.tester, this.data, this.boundary, this._semantics);

  GoRouter get router {
    final el = tester.element(find.byType(_JourneyApp));
    return ProviderScope.containerOf(el).read(routerProvider);
  }

  /// Current location of the real router: the top page (also a pushed
  /// one, like the app's own `mgCurrentLocation`) + the base URI when it
  /// differs (a pushed page sits on top of it).
  String get location {
    try {
      final r = router;
      final top = mgCurrentLocation(r);
      final base = r.routerDelegate.currentConfiguration.uri.toString();
      return base == top ? top : '$top (pushed over $base)';
    } catch (e) {
      return '?($e)';
    }
  }

  /// Boots the app in [state]. The router starts where the real app starts
  /// (`/login`); its redirect sends a logged-in customer Home. [start] =
  /// optional jump (`router.go`) afterwards.
  static Future<JourneyRig> boot(WidgetTester tester, JourneyState state, {String? start}) async {
    await loadMontserrat();
    await _loadIcons();
    mockPathProvider();
    _mockPlugins();
    MgMotion.resetSession();
    // Onboarding done (language, permissions, intro) — those overlays live
    // in main.dart's MotoGoApp, which the rig does not mount.
    SharedPreferences.setMockInitialValues({'mg_intro_shown': true, 'mg_perms_shown': true});
    final data = journeyData(state);
    journeyBackendData = data;
    await initJourneyBackend();
    await tester.runAsync(() => journeySetLoggedIn(data.loggedIn));
    tester.view.physicalSize = kJourneySize * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(ProviderScope(overrides: journeyOverrides(data), child: _JourneyApp(boundary: key)));
    // Semantics on: the step log names what a tap hit (its label).
    final rig = JourneyRig._(tester, data, key, tester.ensureSemantics());
    await rig.settle();
    if (start != null && start.isNotEmpty) {
      rig.router.go(start);
      await rig.settle();
    }
    return rig;
  }

  /// Pumps until no frame is scheduled (min 0.4 s, max [maxMs]) — looping
  /// animations never settle, so this never waits forever.
  Future<void> settle({int maxMs = 3000}) async {
    await tester.pump();
    var t = 0;
    while (t < maxMs) {
      await tester.pump(const Duration(milliseconds: 100));
      t += 100;
      if (t >= 400 && !tester.binding.hasScheduledFrame) break;
    }
  }

  /// Writes the whole screen (incl. dialogs / sheets) as a 360×780 PNG.
  Future<void> shot(String path) async {
    await tester.runAsync(() async {
      final ro = boundary.currentContext?.findRenderObject();
      if (ro is! RenderRepaintBoundary) return;
      final ui.Image img = await ro.toImage(pixelRatio: 1.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      if (bytes == null) return;
      final f = File(path);
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(bytes.buffer.asUint8List());
    });
  }

  /// Unmounts the app so its timers end with the test.
  /// First leaves for Home (the payment screen writes its providers one
  /// frame after its own dispose, while the app's ProviderScope lives on).
  Future<void> dispose() async {
    try {
      router.go('/');
      await settle(maxMs: 1500);
    } catch (_) {}
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 61));
    _semantics.dispose();
  }
}

class _JourneyApp extends ConsumerWidget {
  final GlobalKey boundary;
  const _JourneyApp({required this.boundary});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return RepaintBoundary(
      key: boundary,
      child: MaterialApp.router(
        title: 'MotoGo24',
        debugShowCheckedModeBanner: false,
        theme: v2TestTheme(),
        routerConfig: mgSafeRouterConfig(router),
        locale: const Locale('cs'),
        supportedLocales: supportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // Like main.dart: no system text scaling; reduced motion on.
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.noScaling, disableAnimations: true),
          child: MgV2Gate(router: router, child: child!),
        ),
      ),
    );
  }
}
