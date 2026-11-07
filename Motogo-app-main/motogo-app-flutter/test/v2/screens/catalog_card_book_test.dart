// Owner 2026-10-22 "nikdy nic vyplňovat dvakrát": with dates set, the
// Motorky card CTA "REZERVOVAT" goes straight to the booking form (bike +
// dates filled, both folded with "Změnit") instead of the detail where
// REZERVOVAT had to be pressed again; photo / no dates still open the detail.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/booking_form_widget.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/core/feature_flags.dart';
import 'package:motogo_app/features/auth/auth_provider.dart' show profileProvider;
import 'package:motogo_app/features/booking/booking_provider.dart';
import 'package:motogo_app/features/booking/my_vouchers.dart';
import 'package:motogo_app/features/booking/v2/booking_date_v2.dart';
import 'package:motogo_app/features/booking/v2/booking_recap_v2.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/v2/moto_card_full_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';
import 'package:motogo_app/features/catalog/widgets/availability_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_booking.dart';
import '../support/fakes_catalog.dart' show catalogOverrides;
import '../support/v2_harness.dart';

const _profile = {
  ...kProfileOk,
  'gear_sizes': {
    'rider': {'helmet': 'L', 'gloves': 'M', 'jacket': 'L', 'pants': 'M'},
  },
};

Future<ProviderContainer> _pump(WidgetTester t, List<Override> overrides) async {
  t.view.physicalSize = const Size(412, 915) * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final router = GoRouter(initialLocation: '/search', routes: [
    GoRoute(path: '/search', builder: (_, __) => const MotorkyScreenV2()),
    GoRoute(path: '/moto/:id', builder: (_, s) => Text('detail:${s.pathParameters['id']}')),
    GoRoute(path: '/booking', builder: (_, __) => const Scaffold(body: BookingDebugWrapper())),
  ]);
  final c = ProviderContainer(overrides: [
    rankTokensProvider.overrideWithValue(RankTokens.forLevel(3)),
    rankArcPctProvider.overrideWithValue(50),
    trailerAvailabilityProvider.overrideWith((ref, r) async => const TrailerAvailability(1, 'tr-1')),
    selfServiceDeliveryEnabledProvider.overrideWith((ref) async => false),
    myVouchersProvider.overrideWith((ref) async => const []),
    ...overrides,
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
  return c;
}

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
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
  final cs = AppTranslations.of('cs');

  testWidgets('dates set: card REZERVOVAT → form with the bike + dates folded', (t) async {
    final c = await _pump(t, catalogOverrides(filter: dated, filtered: [kBmw, kHusq], profile: _profile));
    // In the app the profile is loaded long before (Home, and the list's
    // own loyaltyStatusProvider watches it); the fakes override loyalty.
    c.read(profileProvider);
    await t.pump();
    final cta = find.descendant(of: find.byType(MotoCardFullV2).first, matching: find.byType(MgCta));
    expect(t.widget<MgCta>(cta).label, cs.tr('v2CatCtaBook'));
    await t.tap(cta);
    await _settle(t);
    expect(find.byType(BookingDebugWrapper), findsOneWidget);
    expect(find.descendant(of: find.byType(BookingRecapV2), matching: find.text(kBmw.model)), findsWidgets);
    expect(find.descendant(of: find.byType(BookingDateCardV2), matching: find.text('Změnit')), findsOneWidget);
    expect(find.byType(AvailabilityCalendar), findsNothing);
    final d = c.read(bookingDraftProvider);
    expect([d.motoId, d.startDate, d.endDate, d.helmetSize], ['m-bmw', ws, we, 'L']);
    expect(c.read(bookingMotoProvider)?.id, 'm-bmw');
    expect(c.read(filteredMotoIdsProvider), ['m-bmw', 'm-husq']);
    await _unmount(t);
  });

  testWidgets('dates set: the photo still opens the detail', (t) async {
    final c = await _pump(t, catalogOverrides(filter: dated, filtered: [kBmw, kHusq]));
    await t.tapAt(t.getTopLeft(find.byType(MotoCardFullV2).first) + const Offset(206, 140));
    await _settle(t);
    expect(find.text('detail:m-bmw'), findsOneWidget);
    expect(c.read(bookingDraftProvider).motoId, isNull);
    await _unmount(t);
  });

  testWidgets('no dates: card CTA "Vybrat" → detail with the shown sibling ids', (t) async {
    final c = await _pump(t, catalogOverrides(filtered: [kBmw, kHusq, kKids]));
    final cta = find.descendant(of: find.byType(MotoCardFullV2).first, matching: find.byType(MgCta));
    expect(t.widget<MgCta>(cta).label, cs.tr('v2CatCtaPick'));
    await t.tap(cta);
    await _settle(t);
    expect(find.text('detail:m-bmw'), findsOneWidget);
    expect(c.read(filteredMotoIdsProvider), ['m-bmw', 'm-husq', 'm-kid']);
    expect(c.read(bookingDraftProvider).motoId, isNull);
    await _unmount(t);
  });
}
