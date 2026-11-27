// THROWAWAY visual review of the calculator with delivery (delete after use).
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
import 'package:motogo_app/core/booking_form_locked_option.dart';
import 'package:motogo_app/core/booking_form_pickup_section.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/router.dart';
import 'package:motogo_app/core/safe_router_config.dart';
import 'package:motogo_app/core/v2/flag/v2_gate.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/auth/auth_provider.dart';
import 'package:motogo_app/features/booking/v2/booking_v2_parts.dart';
import 'package:motogo_app/features/booking/v2/sections/price_v2.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_receipt_v2.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_state.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_step_handover_v2.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_total_v2.dart';
import 'package:motogo_app/features/catalog/v2/catalog_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'journey/journey_backend.dart';
import 'journey/journey_overrides.dart';
import 'journey/journey_states.dart';
import 'support/fakes_calc_delivery.dart';
import 'support/fakes_catalog.dart' show futureWeekend, kBmw;
import 'support/fakes_home.dart' show mockPathProvider;
import 'support/fakes_reservations.dart' show registerReservationStrings;
import 'support/v2_harness.dart' show loadMontserrat, v2TestTheme;

final _out = Platform.environment['MG_CALC_SHOTS'] ?? '/tmp/calc_shots';
String _cs(String k) => translations['cs']![k]!;

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
}

class _App extends ConsumerWidget {
  final GlobalKey boundary;
  const _App(this.boundary);
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
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.noScaling, disableAnimations: true),
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

  Future<void> settle([int maxMs = 2500]) async {
    await t.pump();
    var ms = 0;
    while (ms < maxMs) {
      await t.pump(const Duration(milliseconds: 100));
      ms += 100;
      if (ms >= 500 && !t.binding.hasScheduledFrame) break;
    }
  }

  Future<void> shot(String name) async {
    final ex = t.takeException();
    if (ex != null) stdout.writeln('EXCEPTION before $tag/$name: $ex');
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

  Future<void> show(Finder f, {double align = 0.35}) async {
    if (f.evaluate().isEmpty) {
      stdout.writeln('MISSING $tag: $f');
      return;
    }
    await Scrollable.ensureVisible(t.element(f.first), alignment: align);
    await settle(800);
  }

  Future<void> tap(Finder f, {double align = 0.4}) async {
    if (f.evaluate().isEmpty) {
      stdout.writeln('MISSING TAP $tag: $f');
      return;
    }
    await show(f, align: align);
    await t.tap(f.first, warnIfMissed: false);
    await settle();
  }
}

Future<Rig> boot(WidgetTester t, Size size) async {
  await loadMontserrat();
  await _loadIcons();
  registerReservationStrings();
  mockPathProvider();
  _mockPlugins();
  MgMotion.resetSession();
  final data = journeyData(JourneyState.ready);
  SharedPreferences.setMockInitialValues({'mg_intro_shown': true, 'mg_perms_shown': true});
  journeyBackendData = data;
  await initJourneyBackend();
  await t.runAsync(() => journeySetLoggedIn(true));
  t.view.physicalSize = size * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final key = GlobalKey();
  await t.pumpWidget(ProviderScope(overrides: [
    ...journeyOverrides(data, v2: true),
    profileProvider.overrideWith((ref) async => kProfileJihlava),
  ], child: _App(key)));
  final r = Rig(t, key, '${size.width.toInt()}x${size.height.toInt()}');
  await r.settle(3000);
  return r;
}

Finder _opt(String title) => find.byWidgetPredicate((w) => w is BkOptionRow && w.title == title);

Future<void> flow(WidgetTester t, Size size) async {
  final r = await boot(t, size);
  final (ws, we) = futureWeekend();
  r.c.read(calcStateProvider.notifier).prefill(motoId: 'm-bmw', start: ws, end: we);
  r.c.read(catalogModeProvider.notifier).state = CatalogMode.calc;
  r.c.read(catalogCalcRequestProvider.notifier).state = true;
  r.router.go('/search');
  await r.settle(3000);
  final step = find.byType(CalcStepHandoverV2);
  await r.show(step, align: 0.12);
  await r.shot('01_step4_before');
  await r.tap(_opt(_cs('v2BkDeliveryTo')));
  await r.show(step, align: 0.12);
  await r.shot('02_delivery_no_address');
  await r.show(find.byType(CalcTotalV2), align: 0.3);
  await r.shot('02b_total_missing_address');
  await r.tap(find.text(_cs('v2BkEnterAddress')));
  await r.shot('03_sheet');
  await t.tap(find.text(_cs('bkAddrMine')));
  await r.settle();
  await r.shot('04_sheet_routed');
  await t.tap(find.text(_cs('v2AddrConfirm')));
  await r.settle();
  await r.show(step, align: 0.12);
  await r.shot('05_step4_delivery_fee');
  await r.tap(_opt(_cs('v2BkReturnFrom')));
  await r.show(find.byType(BookingFormPickupSection), align: 0.05);
  await r.shot('06_step4_both_sides');
  await r.show(find.byType(CalcStepHandoverV2), align: 0.95);
  await r.shot('06b_step4_both_sides_end');
  await r.show(find.byType(CalcReceiptV2), align: 0.1);
  await r.shot('07_receipt');
  await r.show(find.byType(CalcTotalV2), align: 0.3);
  await r.shot('08_total');
  // Self-service bike.
  final own = r.c.read(calcStateProvider).handover;
  r.c.read(calcStateProvider.notifier).setMoto('m-husq');
  await r.settle();
  await r.show(step, align: 0.12);
  await r.shot('09_self_service');
  await r.tap(find.byType(BookingLockedOptionTile));
  await r.show(step, align: 0.12);
  await r.shot('10_self_service_open');
  // Back to the BMW with the delivery, then the booking form.
  r.c.read(calcStateProvider.notifier).setMoto('m-bmw');
  await r.settle();
  r.c.read(calcStateProvider.notifier)
      .updateHandover((c) => own!.choice, seed: own!.choice, branchId: kBmw.branchId, owner: own.owner);
  await r.settle();
  await r.show(find.byType(CalcTotalV2), align: 0.3);
  await r.tap(find.descendant(of: find.byType(CalcTotalV2), matching: find.byType(MgCta)));
  await r.settle(3000);
  await r.shot('11_form_top');
  await r.show(find.byType(BookingFormPickupSection), align: 0.1);
  await r.shot('12_form_pickup');
  await r.show(find.byType(BookingPriceV2), align: 0.2);
  await r.shot('13_form_price');
  try {
    r.router.go('/');
    await r.settle(1500);
  } catch (_) {}
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 61));
}

void main() {
  testWidgets('shots 360x780', (t) => deliveryNet(() => flow(t, const Size(360, 780))));
  testWidgets('shots 320x640', (t) => deliveryNet(() => flow(t, const Size(320, 640))));
}
