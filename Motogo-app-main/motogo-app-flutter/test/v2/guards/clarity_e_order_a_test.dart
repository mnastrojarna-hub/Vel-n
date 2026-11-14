// Clarity "order-a" (second customer walk, new look): P2-05 "Ukázat proč"
// for missing gear sizes lands on the size buttons themselves; P2-07 the
// licence problem is said in the detail dock BEFORE dates too (same text as
// after dates, "VYBRAT TERMÍN" quieter but the same tap); P2-08 the detail
// dock's amount stays the list price (old look) and is labelled "před
// slevou" when the catalog card showed a lower rank price. Display only:
// canProceed, prices and every tap target are unchanged.
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
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/booking/v2/booking_dock_v2.dart';
import 'package:motogo_app/features/booking/v2/booking_form_view_v2.dart';
import 'package:motogo_app/features/booking/v2/sections/extras_rows_v2.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_detail_screen.dart';
import 'package:motogo_app/features/catalog/moto_model.dart' show BookedDateRange;
import 'package:motogo_app/features/catalog/v2/detail/detail_dock_v2.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_trip_card_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_booking.dart';
import '../support/fakes_catalog.dart';
import '../support/v2_harness.dart';

final _cs = AppTranslations.of('cs');
final _shot = GlobalKey();

const _bd = PriceBreakdown(
    basePrice: 12261, extrasTotal: 0, pickupDeliveryFee: 0, returnDeliveryFee: 0, discountTotal: 368, total: 11893, days: 3);

Future<void> _form(WidgetTester t, {required List<String> missing}) async {
  final draft = bookingDraft(kBmw, sizes: false);
  await pumpV2(
    t,
    BookingFormV2View(
      moto: kBmw,
      draft: draft,
      bd: _bd,
      pricedExtras: const [],
      err: null,
      profileErr: null,
      hasDates: true,
      dayCount: 3,
      isKids: false,
      selfService: false,
      selfServiceAtBranch: false,
      hideReturnTime: false,
      deliveryBlocked: false,
      branchLabel: 'Mezná',
      missingSizes: missing,
      canProceed: false,
      booked: const AsyncValue.data(<BookedDateRange>[]),
      calOpen: false,
      onCloseCalendar: () {},
      noteOpen: false,
      noteCtrl: TextEditingController(),
      onUpd: (_) {},
      onBack: () {},
      onOpenCalendar: () {},
      onDatesSelected: (_, __) {},
      onDatesReset: () {},
      onRetryBooked: () {},
      onPickupTime: (_) {},
      onReturnTime: (_) {},
      onToggleNote: () {},
      onNoteChanged: (_) {},
      onVop: (_) {},
      onGdpr: (_) {},
      onKids: (_) {},
      onProceed: () {},
      onCompleteProfile: () {},
    ),
    overrides: bookingOverrides(moto: kBmw, draft: draft),
    boundaryKey: _shot,
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

Future<void> _detail(WidgetTester t, List<Override> overrides, {String lang = 'cs', Size size = const Size(412, 915)}) async {
  t.view.physicalSize = size * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final router = GoRouter(initialLocation: '/moto/m-bmw', routes: [
    GoRoute(path: '/moto/:id', builder: (_, s) => MotoDetailScreen(motoId: s.pathParameters['id']!)),
    GoRoute(path: '/booking', builder: (_, __) => const Text('booking-page')),
  ]);
  final c = ProviderContainer(overrides: [
    rankTokensProvider.overrideWithValue(RankTokens.forLevel(3)),
    rankArcPctProvider.overrideWithValue(50),
    ...overrides,
  ]);
  addTearDown(c.dispose);
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: RepaintBoundary(
      key: _shot,
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
          enabled: true,
          child: MediaQuery(data: MediaQuery.of(ctx).copyWith(disableAnimations: true), child: child!),
        ),
      ),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _done(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 2));
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerBookingStrings();
    registerCatalogStrings();
    mockBookingPathProvider();
  });
  setUp(() {
    MgMotion.resetSession();
    SharedPreferences.setMockInitialValues({});
  });
  final a2 = <String, dynamic>{'license_group': ['A2']};

  testWidgets('P2-05: missing sizes → "Ukázat proč" brings the size buttons into view', (t) async {
    await _form(t, missing: [_cs.tr('helmet')]);
    expect(t.widget<BookingDockV2>(find.byType(BookingDockV2)).blocker, _cs.tr('v2BkBlockSizes'));
    // Scroll to the very bottom (consents / amber card), as the customer was.
    await t.drag(find.byType(Scrollable).first, const Offset(0, -4000));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(BookingGearRowV2).hitTestable(), findsNothing);
    final why = find.descendant(
        of: find.byType(BookingDockV2),
        matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.label == _cs.tr('coBkShowWhy')));
    await t.tap(why);
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(BookingGearRowV2).hitTestable(), findsWidgets, reason: 'the size buttons, not the amber card');
    await maybeShot(t, _shot, 'e_order_a__booking_sizes_why__cs__412x915');
    await _done(t);
  });

  testWidgets('P2-07: A2 profile, no dates → red licence line in the dock, quiet VYBRAT TERMÍN, same tap', (t) async {
    await _detail(t, catalogOverrides(profile: a2));
    final dock = find.byType(DetailDockV2);
    final warn = find.descendant(of: dock, matching: find.byKey(const ValueKey('detail-dock-warning')));
    expect(warn, findsOneWidget);
    expect(find.descendant(of: warn, matching: find.textContaining('A2')), findsOneWidget, reason: 'the validator text');
    final ghost = find.descendant(of: dock, matching: find.byKey(const ValueKey('detail-dock-pick-ghost')));
    expect(ghost, findsOneWidget);
    expect(find.descendant(of: dock, matching: find.byType(MgCta)), findsNothing);
    await maybeShot(t, _shot, 'e_order_a__detail_dock_licence_nodates__cs__412x915');
    expect(find.byType(DetailTripCardV2).hitTestable(), findsNothing, reason: 'below the photo at first');
    await t.tap(ghost);
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('booking-page'), findsNothing);
    expect(t.widget<DetailTripCardV2>(find.byType(DetailTripCardV2)).calendarExpanded, isTrue);
    expect(find.byType(DetailTripCardV2).hitTestable(), findsOneWidget, reason: 'brings the date step up as before');
    await _done(t);
  });

  testWidgets('P2-07: A profile, no dates → bright VYBRAT TERMÍN as before', (t) async {
    await _detail(t, catalogOverrides(profile: {'license_group': ['A']}));
    final dock = find.byType(DetailDockV2);
    expect(find.descendant(of: dock, matching: find.byKey(const ValueKey('detail-dock-warning'))), findsNothing);
    expect(t.widget<MgCta>(find.descendant(of: dock, matching: find.byType(MgCta))).loop, isTrue);
    await _done(t);
  });

  testWidgets('P2-07: German 320 px dock fits', (t) async {
    await _detail(t, catalogOverrides(profile: a2), lang: 'de', size: const Size(320, 690));
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('detail-dock-pick-ghost')), findsOneWidget);
    await maybeShot(t, _shot, 'e_order_a__detail_dock_licence_nodates__de__320x690');
    await _done(t);
  });

  final (ws, we) = futureWeekend();
  testWidgets('P2-08: rank discount → list price labelled "před slevou", amount unchanged', (t) async {
    await _detail(t, catalogOverrides(filter: CatalogFilter(startDate: ws, endDate: we), profile: {'license_group': ['A']}));
    final dock = find.byType(DetailDockV2);
    final w = t.widget<DetailDockV2>(dock);
    expect(w.listPriceNote, isTrue);
    expect(find.descendant(of: dock, matching: find.text(_cs.tr('coBkListPrice'))), findsOneWidget);
    final cta = t.widget<MgCta>(find.descendant(of: dock, matching: find.byType(MgCta)));
    expect(cta.price, w.price, reason: 'the list price as in the old look');
    await maybeShot(t, _shot, 'e_order_a__detail_dock_list_price__cs__412x915');
    await _done(t);
  });

  testWidgets('P2-08: no discount → no label', (t) async {
    await _detail(
        t, catalogOverrides(filter: CatalogFilter(startDate: ws, endDate: we), profile: {'license_group': ['A']}, loyalty: null));
    expect(find.text(_cs.tr('coBkListPrice')), findsNothing);
    await _done(t);
  });

  testWidgets('P2-08: German 320 px dock fits', (t) async {
    await _detail(t, catalogOverrides(filter: CatalogFilter(startDate: ws, endDate: we), profile: {'license_group': ['A']}),
        lang: 'de', size: const Size(320, 690));
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('detail-dock-list-price')), findsOneWidget);
    await maybeShot(t, _shot, 'e_order_a__detail_dock_list_price__de__320x690');
    await _done(t);
  });
}
