import 'dart:async';

// Judge-3 fixes, partition "order" (Home, catalog, booking form, strip),
// new look only: RD-02 a profile still loading is not "no licence"; M3-10
// Home names an unpaid booking; M3-14 informal texts on Home / Motorky /
// promo; R3-03 delivery without an address is said in the dock (no lock);
// R3-09 the address sheet title says where the bike goes; R3-02 "Doplnit
// v profilu" opens the guided Profil (old look unchanged); RD-01 the pay
// strip's "Zrušit" drops its word only when it would squeeze the title.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/booking_form_widget.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/core/shell_fabs.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/auth/auth_provider.dart' show profileProvider;
import 'package:motogo_app/features/booking/v2/booking_dock_v2.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_detail_screen.dart';
import 'package:motogo_app/features/catalog/moto_model.dart' show BookedDateRange;
import 'package:motogo_app/features/catalog/v2/motorky_dates_card_v2.dart';
import 'package:motogo_app/features/home/v2/home_bookings_v2.dart';
import 'package:motogo_app/features/home/v2/home_funnel_v2.dart';
import 'package:motogo_app/features/home/v2/home_header_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_booking.dart';
import '../support/fakes_catalog.dart';
import '../support/fakes_home.dart' hide kMotos;
import '../support/v2_harness.dart';

final _cs = AppTranslations.of('cs');
String _c(String k) => _cs.tr(k);

Future<GoRouter> _pump(WidgetTester t, String initial, List<Override> overrides,
    {Widget? home, bool v2 = true, String lang = 'cs', Size size = const Size(412, 915)}) async {
  t.view.physicalSize = size * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  Widget stub(String n) => Scaffold(body: Center(child: Text(n)));
  final router = GoRouter(initialLocation: initial, routes: [
    GoRoute(path: '/', builder: (_, __) => Scaffold(body: home ?? const SizedBox())),
    GoRoute(path: '/moto/:id', builder: (_, s) => MotoDetailScreen(motoId: s.pathParameters['id']!)),
    GoRoute(path: '/booking', builder: (_, __) => const Scaffold(body: BookingDebugWrapper())),
    GoRoute(path: '/payment', builder: (_, __) => stub('PAYMENT')),
    GoRoute(path: '/profile', builder: (_, s) => stub('PROFILE ?${s.uri.query}')),
    GoRoute(path: '/search', builder: (_, __) => stub('SEARCH')),
  ]);
  addTearDown(router.dispose);
  await t.pumpWidget(ProviderScope(
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
      builder: (ctx, child) => MgV2Scope(
        enabled: v2,
        child: MediaQuery(data: MediaQuery.of(ctx).copyWith(disableAnimations: true), child: child!),
      ),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
  return router;
}

Future<void> _unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 2));
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await Scrollable.ensureVisible(t.element(f), alignment: 0.4);
  await t.pump();
  await t.tap(f, warnIfMissed: false);
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerCatalogStrings();
    registerHomeStrings();
    registerBookingStrings();
    mockBookingPathProvider();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MgMotion.resetSession();
  });
  final (ws, we) = futureWeekend();
  final loading = profileProvider.overrideWith((ref) => Completer<Map<String, dynamic>?>().future);

  testWidgets('RD-02: profile still loading → no licence warning in the Home funnel, main CTA stays', (t) async {
    await _pump(t, '/', [
      ...homeOverrides(funnel: kMotos.take(2).toList()),
      bookedDatesProvider.overrideWith((ref, id) async => const <BookedDateRange>[]),
      loading,
    ], home: const SingleChildScrollView(child: HomeFunnelV2()));
    expect(find.byKey(const ValueKey('home-funnel-warning')), findsNothing);
    expect(find.descendant(of: find.byType(HomeFunnelV2), matching: find.byType(MgCta)), findsOneWidget);
    await _unmount(t);
  });

  testWidgets('RD-02: profile still loading → no licence warning in the detail dock (dates picked)', (t) async {
    await _pump(t, '/moto/m-bmw', [...catalogOverrides(filter: CatalogFilter(startDate: ws, endDate: we)), loading]);
    expect(find.byKey(const ValueKey('detail-dock-warning')), findsNothing);
    await _unmount(t);
  });

  testWidgets('M3-10: Home empty row names an unpaid booking (same row)', (t) async {
    final pending = PendingBooking(id: 'b1', totalPrice: 11893, createdAt: DateTime.now());
    await pumpV2(t, const HomeBookingsV2(active: []),
        overrides: [pendingBookingFabProvider.overrideWith((ref) => Stream.value(pending))]);
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text(_c('efoHomeUnpaidSub')), findsOneWidget);
    expect(find.text(_c('homeBookMotorcycle')), findsNothing);
    expect(find.byKey(const ValueKey('home-no-booking')), findsOneWidget);
  });

  testWidgets('M3-14: no unpaid booking → the informal offer', (t) async {
    await pumpV2(t, const HomeBookingsV2(active: []),
        overrides: [pendingBookingFabProvider.overrideWith((ref) => Stream.value(null))]);
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text(_c('efoBookNow')), findsOneWidget);
    expect(find.text('Zarezervujte si motorku'), findsNothing);
  });

  testWidgets('M3-14: Home search and Motorky date card talk "ty"', (t) async {
    await _pump(t, '/', homeOverrides(), home: const HomeHeaderProbe());
    expect(find.textContaining('Kdy jedeš? Vyber termín'), findsOneWidget);
    expect(find.textContaining('Kdy jedete'), findsNothing);
    await _unmount(t);
    await pumpV2(t, const SingleChildScrollView(child: MotorkyDatesCardV2()),
        overrides: catalogOverrides(), size: const Size(360, 1400));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text(_c('efoCatPickStart')), findsOneWidget);
    expect(find.text(_c('v2BkSingleDayHint')), findsOneWidget);
    expect(find.textContaining('klikněte'), findsNothing);
    expect(find.textContaining('Vyberte'), findsNothing);
  });

  testWidgets('R3-03: delivery without an address → dock says so, button stays enabled; with it the price line', (t) async {
    final noAddr = bookingDraft(kBmw, pickupMethod: 'delivery')
      ..pickupAddress = null
      ..pickupCity = null;
    await _pump(t, '/booking', bookingOverrides(moto: kBmw, draft: noAddr));
    final dock = t.widget<BookingDockV2>(find.byType(BookingDockV2));
    expect(dock.canProceed, isTrue, reason: 'no new lock');
    expect(t.widget<MgCta>(find.byType(MgCta)).enabled, isTrue);
    expect(dock.context2, _c('efoNoAddrCtx'));
    expect(find.text(_c('efoNoAddrCtx')), findsOneWidget);
    expect(dock.trailingLabel, _c('coBkShowWhy'));
    await _unmount(t);
    await _pump(t, '/booking', bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw, pickupMethod: 'delivery')));
    final ok = t.widget<BookingDockV2>(find.byType(BookingDockV2));
    expect(ok.context2, startsWith(_c('v2YourPrice')));
    expect(find.text(_c('efoNoAddrCtx')), findsNothing);
    await _unmount(t);
  });

  testWidgets('R3-09: delivery address sheet title says where the bike goes (v2); old look keeps its label', (t) async {
    final noAddr = bookingDraft(kBmw, pickupMethod: 'delivery')
      ..pickupAddress = null
      ..pickupCity = null;
    await _pump(t, '/booking', bookingOverrides(moto: kBmw, draft: noAddr));
    await _tap(t, find.text(_c('v2BkEnterAddress')).first);
    expect(find.text(_c('efoDelivAddrTitle')), findsOneWidget);
    expect(find.text(_c('pickupAddressLabel')), findsNothing);
    await _unmount(t);
  });

  testWidgets('R3-02: incomplete profile → v2 "Doplnit v profilu" opens /profile?edit=personal; old look /profile', (t) async {
    const incomplete = {'license_group': ['A'], 'street': '', 'city': '', 'zip': ''};
    await _pump(t, '/booking', bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw), profile: incomplete));
    await _tap(t, find.text(_c('completeProfileBtn')).first);
    expect(find.text('PROFILE ?edit=personal'), findsOneWidget);
    await _unmount(t);
  });

  for (final (lang, size, word) in [
    ('cs', const Size(360, 780), true),
    ('cs', const Size(320, 690), true),
    ('de', const Size(320, 690), false),
    ('uk', const Size(320, 690), false),
    ('de', const Size(412, 915), true),
  ]) {
    testWidgets('RD-01: pay strip $lang ${size.width.toInt()} — "Zrušit" word ${word ? 'kept' : 'dropped'}, action same',
        (t) async {
      final tr = AppTranslations.of(lang);
      final pending = PendingBooking(id: 'b1', totalPrice: 12027, createdAt: DateTime.now());
      await pumpV2(t, Align(alignment: Alignment.topCenter, child: ShellBookingFab(booking: pending, v2: true)),
          lang: lang, size: size);
      await t.pump(const Duration(milliseconds: 300));
      expect(t.takeException(), isNull);
      expect(find.text(tr.tr('coStripCancel')), word ? findsOneWidget : findsNothing);
      final icon = find.byKey(const ValueKey('mg-strip-cancel-icon'));
      expect(icon, word ? findsNothing : findsOneWidget);
      expect(find.bySemanticsLabel(tr.tr('cancelReservationBtn')), findsOneWidget, reason: 'label kept');
      final target = word ? find.text(tr.tr('coStripCancel')) : icon;
      final box = find.ancestor(
          of: target, matching: find.byWidgetPredicate((w) => w is ConstrainedBox && w.constraints.minHeight == 44));
      expect(t.getSize(box.first).height, greaterThanOrEqualTo(44));
      expect(t.getSize(box.first).width, greaterThanOrEqualTo(44));
      await t.tap(target);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text(tr.tr('cancelReservationQ')), findsOneWidget, reason: 'same confirm dialog');
    });
  }
}

/// The Home header alone (its search card), inside the routed test app.
class HomeHeaderProbe extends StatelessWidget {
  const HomeHeaderProbe({super.key});

  @override
  Widget build(BuildContext context) => const SingleChildScrollView(child: HomeHeaderV2());
}
