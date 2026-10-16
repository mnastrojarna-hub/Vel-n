// v2 booking form — behaviour parity (PLAN §3.3 / §5.6): flag OFF draws the
// old tree, flag ON the v2 view; every v2 control calls the form's EXISTING
// action (draft writes, CTA → /payment only when allowed, back target,
// profile fix, promo remove, trailer, own gear, note).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/booking_form_header_widget.dart';
import 'package:motogo_app/core/booking_form_widget.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/core/v2/widgets/mg_back_v2.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/core/v2/widgets/mg_inputs.dart';
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/booking/booking_provider.dart';
import 'package:motogo_app/features/booking/v2/booking_form_view_v2.dart';
import 'package:motogo_app/features/booking/v2/booking_v2_parts.dart';
import 'package:motogo_app/features/booking/v2/sections/extras_rows_v2.dart';
import 'package:motogo_app/features/booking/v2/sections/promo_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_booking.dart';
import '../support/v2_harness.dart';

/// Pumps `/booking` inside a real GoRouter with stub targets; returns the
/// provider container (to read the draft).
Future<ProviderContainer> _pumpRouted(WidgetTester tester, List<Override> overrides, {bool v2 = true}) async {
  tester.view.physicalSize = const Size(412, 915) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  Widget stub(String name) => Scaffold(body: Center(child: Text(name)));
  final router = GoRouter(initialLocation: '/booking', routes: [
    GoRoute(path: '/booking', builder: (_, __) => const Scaffold(body: BookingDebugWrapper())),
    GoRoute(path: '/payment', builder: (_, __) => stub('PAYMENT')),
    GoRoute(path: '/profile', builder: (_, __) => stub('PROFILE')),
    GoRoute(path: '/search', builder: (_, __) => stub('SEARCH')),
    GoRoute(path: '/moto/:id', builder: (_, s) => stub('MOTO ${s.pathParameters['id']}')),
  ]);
  final container = ProviderContainer(overrides: [
    rankTokensProvider.overrideWithValue(RankTokens.forLevel(3)),
    rankArcPctProvider.overrideWithValue(50),
    ...overrides,
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
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
      builder: (context, child) => MgV2Scope(
        enabled: v2,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true, textScaler: TextScaler.noScaling),
          child: child!,
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return container;
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f, warnIfMissed: false);
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
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

  testWidgets('flag OFF → old form, no v2 view', (t) async {
    await _pumpRouted(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw)), v2: false);
    expect(find.byType(BookingFormHeader), findsOneWidget);
    expect(find.byType(BookingFormV2View), findsNothing);
    expect(find.byType(MgCta), findsNothing);
  });

  testWidgets('flag ON → v2 view, old header gone', (t) async {
    await _pumpRouted(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw)));
    expect(find.byType(BookingFormV2View), findsOneWidget);
    expect(find.byType(BookingFormHeader), findsNothing);
  });

  testWidgets('flag OFF / ON without a bike', (t) async {
    await _pumpRouted(t, bookingOverrides(moto: null), v2: false);
    expect(find.byType(BookingNoMotoV2), findsNothing);
    await _pumpRouted(t, bookingOverrides(moto: null));
    expect(find.byType(BookingNoMotoV2), findsOneWidget);
  });

  testWidgets('complete → CTA pushes /payment', (t) async {
    await _pumpRouted(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw)));
    final cta = t.widget<MgCta>(find.byType(MgCta));
    expect(cta.enabled, isTrue);
    await _tap(t, find.byType(MgCta));
    expect(find.text('PAYMENT'), findsOneWidget);
  });

  testWidgets('consents off → CTA locked; ticking both unlocks it', (t) async {
    final c = await _pumpRouted(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw, consents: false)));
    expect(t.widget<MgCta>(find.byType(MgCta)).enabled, isFalse);
    await _tap(t, find.byType(MgCta));
    expect(find.text('PAYMENT'), findsNothing);
    await _tap(t, find.byType(MgCheckRow).at(1)); // VOP (0 = own gear)
    await _tap(t, find.byType(MgCheckRow).at(2)); // GDPR
    expect(c.read(bookingDraftProvider).consentVop, isTrue);
    expect(c.read(bookingDraftProvider).consentGdpr, isTrue);
    expect(t.widget<MgCta>(find.byType(MgCta)).enabled, isTrue);
  });

  testWidgets('missing sizes → locked; a size chip writes the draft, a 2nd tap clears it', (t) async {
    final c = await _pumpRouted(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw, sizes: false)));
    expect(t.widget<MgCta>(find.byType(MgCta)).enabled, isFalse);
    final helmetS = find.descendant(of: find.byType(BookingGearRowV2).first, matching: find.widgetWithText(BkSizeChip, 'S'));
    await _tap(t, helmetS);
    expect(c.read(bookingDraftProvider).helmetSize, 'S');
    expect(t.widget<MgCta>(find.byType(MgCta)).enabled, isTrue);
    await _tap(t, helmetS);
    expect(c.read(bookingDraftProvider).helmetSize, isNull);
  });

  testWidgets('own gear → flag set, sizes cleared, rows hidden', (t) async {
    final c = await _pumpRouted(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw)));
    await _tap(t, find.byType(MgCheckRow).first);
    final d = c.read(bookingDraftProvider);
    expect(d.ownGear, isTrue);
    expect([d.helmetSize, d.glovesSize, d.jacketSize, d.pantsSize], everyElement(isNull));
    expect(find.byType(BookingGearRowV2), findsNothing);
  });

  testWidgets('delivery option writes pickupMethod', (t) async {
    final c = await _pumpRouted(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw)));
    await _tap(t, find.byType(BkOptionRow).at(1));
    expect(c.read(bookingDraftProvider).pickupMethod, 'delivery');
    await _tap(t, find.byType(BkOptionRow).at(0));
    expect(c.read(bookingDraftProvider).pickupMethod, 'store');
  });

  testWidgets('trailer row assigns the free trailer', (t) async {
    final c = await _pumpRouted(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw)));
    await _tap(t, find.byType(BookingExtraRowV2).last);
    final d = c.read(bookingDraftProvider);
    expect(d.trailerMotoId, 'tr-1');
    expect(d.extras.any((e) => e.id == 'extra-vozik'), isTrue);
  });

  testWidgets('promo remove drops the code', (t) async {
    final codes = [AppliedDiscount(code: 'JARO10', type: DiscountType.percent, value: 10)];
    final c = await _pumpRouted(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw, discounts: codes)));
    final remove = find.descendant(of: find.byType(BookingPromoV2), matching: find.bySemanticsLabel('Odebrat kód JARO10'));
    expect(remove, findsOneWidget);
    await _tap(t, remove);
    expect(c.read(bookingDraftProvider).discounts, isEmpty);
  });

  testWidgets('note toggles open and writes notes', (t) async {
    final c = await _pumpRouted(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw)));
    expect(find.byType(TextField), findsNothing);
    await _tap(t, find.text('Poznámka k rezervaci (nepovinné)'));
    expect(find.byType(TextField), findsOneWidget);
    await t.enterText(find.byType(TextField), '  Přijedu autem  ');
    await t.pump();
    expect(c.read(bookingDraftProvider).notes, 'Přijedu autem');
  });

  testWidgets('incomplete profile → "Doplnit v profilu" pushes /profile', (t) async {
    await _pumpRouted(
        t,
        bookingOverrides(
            moto: kBmw, draft: bookingDraft(kBmw), profile: const {'license_group': ['A'], 'street': '', 'city': '', 'zip': ''}));
    expect(t.widget<MgCta>(find.byType(MgCta)).enabled, isFalse);
    await _tap(t, find.text('Doplnit v profilu'));
    expect(find.text('PROFILE'), findsOneWidget);
  });

  testWidgets('back without history → bike detail (old target)', (t) async {
    await _pumpRouted(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw)));
    await _tap(t, find.byType(MgV2Back));
    expect(find.text('MOTO m-bmw'), findsOneWidget);
  });
}
