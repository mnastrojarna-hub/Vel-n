// Owner decisions 2026-11-14 ("Jo, vsechno ano"), new look:
// D1 (M3-04) "Vybrat jinou motorku" on the blocked booking form opens the
//    bike list (Motorky root) for the same dates, not the same bike again.
// D3 (RGO-2) a re-opened draft drops its discount / voucher codes (and so
//    their discount), as the old look's fresh draft did; dates and sizes stay.
//    Form -> payment -> back within one visit keeps the code.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/booking_form_widget.dart';
import 'package:motogo_app/core/feature_flags.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/features/booking/booking_entry.dart';
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/booking/booking_provider.dart';
import 'package:motogo_app/features/booking/my_vouchers.dart';
import 'package:motogo_app/features/booking/v2/booking_form_view_v2.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_detail_page.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_booking.dart';
import '../support/fakes_catalog.dart' show catalogOverrides;
import '../support/v2_harness.dart';

String _tr(String key) => translations['cs']![key]!;

Future<(GoRouter, ProviderContainer)> _pump(WidgetTester t, Map<String, dynamic> profile, CatalogFilter filter) async {
  t.view.physicalSize = const Size(412, 915) * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final router = GoRouter(initialLocation: '/search', routes: [
    GoRoute(path: '/search', builder: (_, __) => const MotorkyScreenV2()),
    GoRoute(path: '/moto/:id', builder: (_, s) => MotoDetailPage(motoId: s.pathParameters['id']!, showBackButton: true)),
    GoRoute(path: '/booking', builder: (_, __) => const Scaffold(body: BookingDebugWrapper())),
    GoRoute(path: '/payment', builder: (_, __) => const Text('PAYMENT')),
  ]);
  final c = ProviderContainer(overrides: [
    rankTokensProvider.overrideWithValue(RankTokens.forLevel(3)),
    rankArcPctProvider.overrideWithValue(50),
    trailerAvailabilityProvider.overrideWith((ref, r) async => const TrailerAvailability(1, 'tr-1')),
    selfServiceDeliveryEnabledProvider.overrideWith((ref) async => false),
    myVouchersProvider.overrideWith((ref) async => const []),
    ...catalogOverrides(filter: filter, profile: profile),
  ]);
  addTearDown(c.dispose);
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
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
      builder: (ctx, child) => MgV2Scope(
        enabled: true,
        child: MediaQuery(data: MediaQuery.of(ctx).copyWith(disableAnimations: true), child: child!),
      ),
    ),
  ));
  await _settle(t);
  return (router, c);
}

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
}

/// The detail's REZERVOVAT (`startBookingFromSelection`) for [ws]–[we].
Future<void> _reserve(WidgetTester t, GoRouter r, DateTime ws, DateTime we) async {
  if (find.byType(MotoDetailPage).evaluate().isEmpty) {
    r.push('/moto/m-bmw');
    await _settle(t);
  }
  final el = t.element(find.byType(MotoDetailPage));
  startBookingFromSelection(el, el as WidgetRef, kBmw, ws, we);
  await _settle(t);
  expect(find.byType(BookingDebugWrapper), findsOneWidget);
}

Future<void> _unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 2));
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerCatalogStrings();
    registerBookingStrings();
    mockBookingPathProvider();
  });
  setUp(() {
    MgMotion.resetSession();
    SharedPreferences.setMockInitialValues({});
  });
  final (ws, we) = futureWeekend();
  final dated = CatalogFilter(startDate: ws, endDate: we);

  testWidgets('D1: licence too low -> "Vybrat jinou motorku" opens the bike list for the dates set in the form', (t) async {
    final (r, c) = await _pump(t, {...kProfileOk, 'license_group': ['A2', 'B']}, dated);
    await _reserve(t, r, ws, we);
    expect(c.read(licenseValidationProvider), isNotNull);
    // SO-2: a date change made in the form reaches the list.
    final ns = ws.add(const Duration(days: 7)), ne = we.add(const Duration(days: 7));
    t.widget<BookingFormV2View>(find.byType(BookingFormV2View)).onDatesSelected(ns, ne);
    await _settle(t);
    final btn = find.text(_tr('pdPickOtherMoto'));
    expect(btn, findsOneWidget);
    await t.ensureVisible(btn);
    await t.pump();
    await t.tap(btn);
    await _settle(t);
    expect(r.routerDelegate.currentConfiguration.uri.path, '/search');
    expect(find.byType(MotorkyScreenV2), findsOneWidget);
    expect(find.byType(MotoDetailPage), findsNothing, reason: 'not back to the same bike');
    expect(find.byType(BookingDebugWrapper), findsNothing);
    final f = c.read(catalogFilterProvider);
    expect([f.startDate, f.endDate], [ns, ne]);
    // The draft stays as after Back (next REZERVOVAT carries it).
    expect(c.read(bookingDraftProvider).motoId, kBmw.id);
    await _unmount(t);
  });

  testWidgets('D3: same visit keeps the code; re-entering the bike drops code + discount, keeps dates and sizes', (t) async {
    final (r, c) = await _pump(t, kProfileOk, dated);
    await _reserve(t, r, ws, we);
    c.read(bookingDraftProvider.notifier).state = c
        .read(bookingDraftProvider)
        .copyWith(helmetSize: () => 'M', notes: () => 'Přijedu vlakem', pickupTime: () => '12:00');
    await t.pump();
    // The same draft without a code = what the re-opened draft must cost.
    final plain = c.read(priceBreakdownProvider);
    final code = AppliedDiscount(code: 'POUKAZ300', type: DiscountType.fixed, value: 300, isVoucher: true);
    c.read(bookingDraftProvider.notifier).state = c.read(bookingDraftProvider).copyWith(discounts: [code]);
    await t.pump();
    final coded = c.read(priceBreakdownProvider);
    expect(coded.discountTotal, greaterThan(0));
    // Form -> payment -> back within one visit: the code was checked now.
    r.push('/payment');
    await _settle(t);
    r.pop();
    await _settle(t);
    var d = c.read(bookingDraftProvider);
    expect(d.discounts.map((x) => x.code), ['POUKAZ300']);
    expect(c.read(priceBreakdownProvider).total, coded.total);
    // Back to the detail and REZERVOVAT again = a re-opened draft.
    r.pop();
    await _settle(t);
    await _reserve(t, r, ws, we);
    d = c.read(bookingDraftProvider);
    expect(d.discounts, isEmpty);
    expect([d.startDate, d.endDate, d.helmetSize, d.notes, d.pickupTime], [ws, we, 'M', 'Přijedu vlakem', '12:00']);
    final again = c.read(priceBreakdownProvider);
    expect(again.discountTotal, 0);
    expect(again.total, plain.total, reason: 'the same total as before the code');
    await _unmount(t);
  });
}
