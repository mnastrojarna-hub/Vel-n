// THROWAWAY visual review of the gear-only rental (delete after use).
// Boots the REAL router + shell (like the journey rig) with gear fakes and
// writes PNGs to MG_GEAR_SHOTS.
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
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/router.dart';
import 'package:motogo_app/core/safe_router_config.dart';
import 'package:motogo_app/core/v2/flag/v2_gate.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/gear_rental/gear_contract.dart';
import 'package:motogo_app/features/gear_rental/gear_done_screen.dart';
import 'package:motogo_app/features/gear_rental/gear_offer_provider.dart';
import 'package:motogo_app/features/gear_rental/gear_order_api.dart';
import 'package:motogo_app/features/gear_rental/gear_order_controller.dart' show gearOrderUserProvider;
import 'package:motogo_app/features/gear_rental/gear_order_state.dart';
import 'package:motogo_app/features/payment/payment_provider.dart';
import 'package:motogo_app/features/reservations/gear/gear_booking_api.dart';
import 'package:motogo_app/features/reservations/reservation_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'journey/journey_backend.dart';
import 'journey/journey_overrides.dart';
import 'journey/journey_states.dart';
import 'support/fakes_home.dart' show mockPathProvider;
import 'support/fakes_reservations.dart' show code, registerReservationStrings;
import 'support/v2_harness.dart' show loadMontserrat, v2TestTheme;

final _out = Platform.environment['MG_GEAR_SHOTS'] ?? '/tmp/gear_shots';

String _d(int k) {
  final n = DateTime.now().add(Duration(days: k));
  return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

const kPrices = [
  GearPrice(key: 'set_no_boots', kind: 'set', label: 'Komplet bez bot', desc: 'Helma, bunda, kalhoty a rukavice', includes: ['helmet', 'jacket', 'pants', 'gloves'], perDay: 490),
  GearPrice(key: 'set_boots', kind: 'set', label: 'Komplet s botami', desc: 'Helma, bunda, kalhoty, rukavice a boty', includes: ['helmet', 'jacket', 'pants', 'gloves', 'boots'], perDay: 890),
  GearPrice(key: 'helmet', kind: 'item', label: 'Helma', sizes: ['XS', 'S', 'M', 'L', 'XL', '2XL'], perDay: 200),
  GearPrice(key: 'jacket', kind: 'item', label: 'Bunda', sizes: ['S', 'M', 'L', 'XL', '2XL', '3XL'], perDay: 200),
  GearPrice(key: 'pants', kind: 'item', label: 'Kalhoty', sizes: ['S', 'M', 'L', 'XL', '2XL', '3XL'], perDay: 150),
  GearPrice(key: 'gloves', kind: 'item', label: 'Rukavice', sizes: ['S', 'M', 'L', 'XL'], perDay: 80),
  GearPrice(key: 'boots', kind: 'item', label: 'Boty', sizes: ['38', '39', '40', '41', '42', '43', '44', '45', '46', '47'], perDay: 400),
];

const kBranches = [
  GearBranch(id: 'm', name: 'Mezná', address: 'Mezná 9, Mezná'),
  GearBranch(id: 'v', name: 'Velké Němčice', address: 'Hlavní 1, Velké Němčice', self: true),
];

class _Api extends GearOrderApi {
  @override
  Future<Map<String, dynamic>> rpc(String fn, Map<String, dynamic> p) async {
    if (fn == 'get_gear_rental_availability') {
      return {
        'enabled': true,
        'sizes': {
          'helmet': {'XS': 1, 'S': 2, 'M': 3, 'L': 0, 'XL': 1, '2XL': 1},
          'boots': {'38': 0, '39': 1, '40': 1, '41': 2, '42': 2, '43': 1, '44': 0, '45': 1, '46': 1, '47': 1},
        },
      };
    }
    if (fn == 'quote_gear_booking') {
      final v = p['p_voucher_code'];
      return {'success': true, 'per_day': 490, 'subtotal': 980, 'amount': v == null ? 980 : 480, 'total': 980,
        if (v != null) 'voucher_amount': 500, if (v != null) 'voucher': {'code': v, 'amount': 500}};
    }
    if (fn == 'create_web_gear_booking') return {'success': true, 'booking_id': 'gnew-1', 'amount': 480, 'total': 980};
    return {};
  }
}

Map<String, dynamic> _gearJson(String id, {String status = 'reserved', String pay = 'paid', int from = 2, int to = 3, bool self = true}) => {
      'id': id,
      'booking_kind': 'gear',
      'booking_number': 'G${id.hashCode.abs() % 99999999}'.padRight(9, '0'),
      'status': status,
      'payment_status': pay,
      'booking_source': 'web',
      'start_date': _d(from),
      'end_date': _d(to),
      'days': to - from + 1,
      'pickup_time': self ? null : '09:00',
      'branch': {
        'id': self ? 'v' : 'm',
        'name': self ? 'MotoGo24 Velké Němčice' : 'MotoGo24 Mezná',
        'address': self ? 'Hlavní 1' : 'Mezná 9',
        'city': self ? 'Velké Němčice' : 'Mezná',
        'type': self ? 'samoobslužná' : 'obslužná',
        'gps_lat': 49.0,
        'gps_lng': 16.6,
      },
      'lines': [
        {'key': 'set_no_boots', 'kind': 'set', 'label': 'Komplet bez bot', 'includes': ['helmet', 'jacket', 'pants', 'gloves'],
          'sizes': {'helmet': 'M', 'jacket': 'L', 'pants': 'L', 'gloves': 'M'}, 'price_per_day': 490},
        {'key': 'boots', 'kind': 'item', 'label': 'Boty', 'includes': ['boots'], 'sizes': {'boots': '43'}, 'price_per_day': 400},
      ],
      'per_day': 890,
      'subtotal': 890.0 * (to - from + 1),
      'total': 890.0 * (to - from + 1),
      'voucher_amount': 0,
      'docs': {'required': true, 'ok': false},
      'created_at': DateTime.now().subtract(const Duration(days: 3)).toUtc().toIso8601String(),
    };

final gUp = Reservation.fromGearRpc(_gearJson('9e000000-0000-4000-8000-000000000001'));
final gDone = Reservation.fromGearRpc(_gearJson('9e000000-0000-4000-8000-000000000002', status: 'completed', from: -9, to: -8, self: false));
final gPend = Reservation.fromGearRpc(_gearJson('9e000000-0000-4000-8000-000000000003', status: 'pending', pay: 'unpaid', from: 6, to: 7, self: false));

JourneyData _data({bool bookings = true}) {
  final b = journeyData(JourneyState.ready);
  return JourneyData(
    state: b.state,
    loggedIn: true,
    profile: b.profile,
    gate: b.gate,
    verification: b.verification,
    loyalty: b.loyalty,
    reservations: bookings ? [gUp, gPend, gDone] : const [],
    codes: {gUp.id: [code('accessories', '4821')]},
  );
}

List<Override> _gear({String? docs}) => [
      gearRentalSettingsProvider.overrideWith((ref) async => const GearRentalSettings(enabled: true, appVisible: true, selfServiceEnabled: true)),
      gearPricesProvider.overrideWith((ref) async => kPrices),
      gearBranchesProvider.overrideWith((ref) async => kBranches),
      gearClosuresProvider.overrideWith((ref) async => const []),
      gearOrderApiProvider.overrideWithValue(_Api()),
      gearOrderUserProvider.overrideWithValue((kJourneyUserId, 'jan.novak@example.cz')),
      gearDocsStatusProvider.overrideWith((ref, id) async => docs),
      gearDoneFetchProvider.overrideWithValue((id) async => {..._gearJson(id, from: 1, to: 2), 'voucher_amount': 500, 'total': 1280}),
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
  final asserts = <String>[];
  Rig(this.t, this.key, this.tag);

  ProviderContainer get c => ProviderScope.containerOf(t.element(find.byType(_App)));
  GoRouter get router => c.read(routerProvider);

  Future<T> guard<T>(Future<T> Function() f) {
    final parent = Zone.current;
    final done = Completer<T>();
    runZoned(() {
      f().then(done.complete, onError: done.completeError);
    }, zoneSpecification: ZoneSpecification(handleUncaughtError: (self, p, zone, e, st) {
      final msg = '$e';
      if (msg.contains('markNeedsBuild() called during build')) {
        asserts.add('markNeedsBuild during build');
        return;
      }
      parent.handleUncaughtError(e, st);
    }));
    return done.future;
  }

  Future<void> settle([int maxMs = 2500]) => guard(() async {
        await t.pump();
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
    await t.runAsync(() async {
      final ro = key.currentContext?.findRenderObject();
      if (ro is! RenderRepaintBoundary) return;
      final ui.Image img = await ro.toImage(pixelRatio: 1.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      if (bytes == null) return;
      final f = File('$_out/${tag}_$name.png');
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(bytes.buffer.asUint8List());
    });
    stdout.writeln('SHOT $tag/$name @ ${_loc()}');
  }

  String _loc() {
    try {
      return router.routerDelegate.currentConfiguration.uri.toString();
    } catch (_) {
      return '?';
    }
  }

  Future<void> go(String p) async {
    router.go(p);
    await settle();
  }

  Future<void> show(Finder f, {double align = 0.35}) async {
    if (f.evaluate().isEmpty) {
      stdout.writeln('MISSING $tag: $f');
      return;
    }
    await guard(() => Scrollable.ensureVisible(t.element(f.first), alignment: align));
    await settle(800);
  }

  Future<void> tap(Finder f) async {
    if (f.evaluate().isEmpty) {
      stdout.writeln('MISSING TAP $tag: $f');
      return;
    }
    await show(f, align: 0.4);
    await guard(() async => t.tap(f.first, warnIfMissed: false));
    await settle();
  }

  /// Scroll the main (largest) vertical scrollable page by page.
  Future<void> pages(String name, {int max = 8}) async {
    await shot('${name}_p0');
    for (var i = 1; i < max; i++) {
      final s = _main();
      if (s == null) return;
      final pos = s.position;
      if (pos.pixels >= pos.maxScrollExtent - 1) return;
      final next = (pos.pixels + t.view.physicalSize.height / t.view.devicePixelRatio * 0.7).clamp(0.0, pos.maxScrollExtent);
      pos.jumpTo(next);
      await settle(800);
      await shot('${name}_p$i');
    }
  }

  ScrollableState? _main() {
    ScrollableState? best;
    double bestH = 0;
    for (final e in find.byType(Scrollable).evaluate()) {
      final s = (e as StatefulElement).state as ScrollableState;
      if (s.axisDirection != AxisDirection.down) continue;
      final ro = e.renderObject;
      if (ro is! RenderBox || !ro.hasSize || !ro.attached) continue;
      final h = ro.size.height * ro.size.width;
      if (s.position.maxScrollExtent > 0 && h > bestH) {
        bestH = h;
        best = s;
      }
    }
    return best;
  }
}

Future<Rig> boot(WidgetTester t, {required bool v2, Size size = const Size(360, 780), bool bookings = true, String? docs}) async {
  await loadMontserrat();
  await _loadIcons();
  registerReservationStrings();
  mockPathProvider();
  _mockPlugins();
  MgMotion.resetSession();
  final data = _data(bookings: bookings);
  SharedPreferences.setMockInitialValues({'mg_intro_shown': true, 'mg_perms_shown': true});
  journeyBackendData = data;
  await initJourneyBackend();
  await t.runAsync(() => journeySetLoggedIn(true));
  t.view.physicalSize = size * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final key = GlobalKey();
  await t.pumpWidget(ProviderScope(overrides: [...journeyOverrides(data, v2: v2), ..._gear(docs: docs)], child: _App(key)));
  final r = Rig(t, key, '${v2 ? 'v2' : 'old'}_${size.width.toInt()}');
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

Future<void> orderFlow(Rig r, {required bool v2, bool full = true}) async {
  // Home
  await r.shot('01_home_top');
  final row = find.byKey(ValueKey(v2 ? 'home-gear-row' : 'home-gear-row-old'));
  await r.show(row, align: 0.5);
  await r.shot('02_home_gear_row');
  await r.tap(row);
  await r.settle(1500);
  await r.shot('03_order_top');
  if (!full) return;
  await r.tap(find.byKey(const ValueKey('gear-branch-m')));
  await r.shot('04_branch_mezna');
  await r.tap(find.byKey(const ValueKey('gear-branch-v')));
  await r.shot('04b_branch_self');
  await r.tap(find.byKey(const ValueKey('gear-branch-m')));
  final ctrl = r.c.read(gearOrderProvider.notifier);
  final n = DateTime.now();
  ctrl.tapDay(DateTime(n.year, n.month, n.day + 1));
  ctrl.tapDay(DateTime(n.year, n.month, n.day + 2));
  await r.settle(1200);
  await r.show(find.byKey(const ValueKey('gear-step-dates')), align: 0.1);
  await r.shot('05_dates');
  await r.show(find.byKey(const ValueKey('gear-step-items')), align: 0.05);
  await r.shot('06_items_empty');
  await r.tap(find.byKey(const ValueKey('gear-set-set_no_boots')));
  await r.show(find.byKey(const ValueKey('gear-step-items')), align: 0.05);
  await r.shot('07_items_set');
  for (final k in ['gear-size-helmet-M', 'gear-size-jacket-L', 'gear-size-pants-L', 'gear-size-gloves-M']) {
    await r.tap(find.byKey(ValueKey(k)));
  }
  await r.show(find.byKey(const ValueKey('gear-item-gloves')), align: 0.5);
  await r.shot('08_items_sized');
  await r.show(find.byKey(const ValueKey('gear-item-boots')), align: 0.5);
  await r.shot('08b_items_boots');
  await r.show(find.byKey(const ValueKey('gear-step-contact')), align: 0.05);
  await r.shot('09_contact');
  ctrl
    ..setVoucherOn(true)
    ..applyVoucher('DAREK500');
  await r.settle(1500);
  await r.show(find.byKey(const ValueKey('gear-voucher')), align: 0.4);
  await r.shot('10_voucher');
  await r.tap(find.byKey(const ValueKey('gear-cta')));
  await r.settle(800);
  await r.shot('11_cta_no_consents');
  await r.tap(find.byKey(const ValueKey('gear-vop')));
  await r.tap(find.byKey(const ValueKey('gear-gdpr')));
  await r.show(find.byKey(const ValueKey('gear-summary')), align: 0.2);
  await r.shot('12_summary');
  final s = r._main();
  if (s != null) {
    s.position.jumpTo(s.position.maxScrollExtent);
    await r.settle(800);
    await r.shot('13_bottom');
  }
  await r.tap(find.byKey(const ValueKey('gear-cta')));
  await r.settle(2500);
  await r.shot('14_payment');
}

Future<void> doneAndRes(Rig r) async {
  r.c.read(gearPaymentIdsProvider.notifier).state = {'gnew-1'};
  r.c.read(lastConfirmedBookingProvider.notifier).state = 'gnew-1';
  await r.go('/success');
  await r.settle(2500);
  await r.pages('20_done', max: 5);
  await r.go('/reservations');
  await r.pages('30_res_list', max: 4);
  await r.go('/');
  await r.settle();
  final card = find.textContaining('Výpůjčka výbavy');
  if (card.evaluate().isNotEmpty) {
    await r.show(card, align: 0.3);
    await r.shot('31_home_gear_card');
  }
  await r.go('/reservations/${gUp.id}');
  await r.pages('40_detail_up', max: 10);
  await r.go('/reservations/${gPend.id}');
  await r.pages('41_detail_pending', max: 3);
  await r.go('/reservations/${gDone.id}');
  await r.pages('42_detail_done', max: 6);
  await r.go('/reservations/${gUp.id}/edit');
  await r.settle(2500);
  await r.pages('50_edit', max: 6);
}

void main() {
  for (final v2 in [true, false]) {
    testWidgets('gear shots ${v2 ? 'v2' : 'old'} 360', (t) async {
      final r = await boot(t, v2: v2);
      await orderFlow(r, v2: v2);
      await doneAndRes(r);
      if (r.asserts.isNotEmpty) stdout.writeln('ASSERTS ${r.asserts.length}');
      await end(r);
    });
    testWidgets('gear shots ${v2 ? 'v2' : 'old'} 320', (t) async {
      final r = await boot(t, v2: v2, size: const Size(320, 640));
      await orderFlow(r, v2: v2);
      await end(r);
    });
    testWidgets('gear docs missing ${v2 ? 'v2' : 'old'}', (t) async {
      final r = await boot(t, v2: v2, docs: 'Chybí OP (líc a rub) nebo pas');
      final rr = Rig(t, r.key, '${r.tag}_nodocs');
      await rr.go('/reservations/${gUp.id}');
      await rr.pages('40_detail_up', max: 4);
      await end(rr);
    });
  }
}
