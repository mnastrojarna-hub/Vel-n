// Catalog fix round 3 (v2, Android): the bike detail and the calculator use
// the booking form's busy rule — the customer's own unpaid draft of the
// same bike (declined card / cancelled 3DS) is not a booked day (the
// payment replaces it, as in the old look); someone else's pending
// booking still blocks.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_detail_page.dart';
import 'package:motogo_app/features/catalog/moto_detail_screen.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_state.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_step_dates_v2.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_sticky_v2.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_total_v2.dart';
import 'package:motogo_app/features/catalog/v2/catalog_mode.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_dock_v2.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_trip_card_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';
import 'package:motogo_app/features/reservations/reservation_models.dart';

import '../support/fakes_catalog.dart';
import '../support/v2_harness.dart';

final _cs = AppTranslations.of('cs');

Future<void> _pump(WidgetTester t, String initial, List<Override> overrides) async {
  t.view.physicalSize = const Size(412, 915) * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final router = GoRouter(initialLocation: initial, routes: [
    GoRoute(path: '/search', builder: (_, __) => const MotorkyScreenV2()),
    GoRoute(path: '/moto/:id', builder: (_, s) => MotoDetailScreen(motoId: s.pathParameters['id']!)),
    GoRoute(path: '/booking', builder: (_, __) => const Text('booking')),
  ]);
  final c = ProviderContainer(overrides: [
    rankTokensProvider.overrideWithValue(RankTokens.forLevel(3)),
    rankArcPctProvider.overrideWithValue(50),
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
  await t.pump();
  await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
}

Future<void> _unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 2));
}

Reservation _draft(String motoId, DateTime s, DateTime e, {String status = 'pending', String paid = 'unpaid'}) =>
    Reservation.fromJson({
      'id': 'own-$motoId',
      'moto_id': motoId,
      'status': status,
      'payment_status': paid,
      'booking_source': 'app',
      'start_date': s.toIso8601String(),
      'end_date': e.toIso8601String(),
      'total_price': 0,
    });

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerCatalogStrings();
  });
  setUp(MgMotion.resetSession);
  final (ws, we) = futureWeekend();
  final dated = CatalogFilter(startDate: ws, endDate: we);
  final pending = [BookedDateRange(start: ws, end: we, status: 'pending')];
  final calcMode = catalogCalcRequestProvider.overrideWith((ref) => true);

  group('detail', () {
    Future<DetailTripCardV2> open(WidgetTester t, List<Reservation> own) async {
      await _pump(t, '/moto/m-husq', catalogOverrides(filter: dated, booked: {'m-husq': pending}, reservations: own));
      return t.widget<DetailTripCardV2>(find.descendant(
          of: find.byWidgetPredicate((w) => w is MotoDetailPage && w.motoId == 'm-husq'),
          matching: find.byType(DetailTripCardV2)));
    }

    MgCta cta(WidgetTester t) =>
        t.widget<MgCta>(find.descendant(of: find.byType(DetailDockV2), matching: find.byType(MgCta)));

    testWidgets('own unpaid draft of this bike: REZERVOVAT enabled, no busy warning', (t) async {
      final trip = await open(t, [_draft('m-husq', ws, we)]);
      expect([trip.busy, trip.calendarExpanded], [false, false]);
      expect(find.text(_cs.tr('v2CalcRangeBusy')), findsNothing);
      expect([cta(t).label, cta(t).onTap != null], [_cs.tr('v2CatCtaBook'), true]);
      await t.tap(find.descendant(of: find.byType(DetailDockV2), matching: find.byType(MgCta)));
      await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
      expect(find.text('booking'), findsOneWidget);
      await _unmount(t);
    });

    testWidgets('someone else\'s pending booking (or own draft of another bike / paid) still blocks', (t) async {
      for (final own in [
        <Reservation>[],
        [_draft('m-bmw', ws, we)],
        [_draft('m-husq', ws, we, paid: 'paid')],
      ]) {
        final trip = await open(t, own);
        expect([trip.busy, trip.calendarExpanded], [true, true]);
        expect(find.text(_cs.tr('v2CalcRangeBusy')), findsOneWidget);
        expect(cta(t).label, _cs.tr('psChangeDates'));
        await _unmount(t);
      }
    });
  });

  group('calculator', () {
    Future<void> open(WidgetTester t, List<Reservation> own) => _pump(t, '/search', [
          ...catalogOverrides(
              calc: CalcState(motoId: 'm-bmw', start: ws, end: we), booked: {'m-bmw': pending}, reservations: own),
          calcMode,
        ]);

    testWidgets('own unpaid draft of this bike: REZERVOVAT enabled', (t) async {
      await open(t, [_draft('m-bmw', ws, we)]);
      expect(t.widget<CalcStepDatesV2>(find.byType(CalcStepDatesV2)).busyInRange, isFalse);
      expect(t.widget<CalcTotalV2>(find.byType(CalcTotalV2)).onBook, isNotNull);
      expect(find.byType(CalcStickyV2), findsOneWidget);
      await _unmount(t);
    });

    testWidgets('someone else\'s pending booking still blocks', (t) async {
      await open(t, const []);
      expect(t.widget<CalcStepDatesV2>(find.byType(CalcStepDatesV2)).busyInRange, isTrue);
      final total = t.widget<CalcTotalV2>(find.byType(CalcTotalV2));
      expect([total.onBook, total.blockedReason], [null, _cs.tr('v2CalcRangeBusy')]);
      expect(find.byType(CalcStickyV2), findsNothing);
      await _unmount(t);
    });
  });
}
