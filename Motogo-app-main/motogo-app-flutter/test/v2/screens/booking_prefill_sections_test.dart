// Owner 2026-10-22 "nikdy nic vyplňovat dvakrát" — booking form sections:
// the return takes the pickup address (+ price) and shows it as an answered
// row ("Stejná jako u přistavení" + "Změnit"); the address sheet offers the
// other side + the profile address; passenger sizes come prefilled from the
// last booking and a chosen extra reopens with its sizes + "Odebrat"; boots
// show "naposledy" but still need a tap; own vouchers are one tap away.
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
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/booking/booking_provider.dart';
import 'package:motogo_app/features/booking/my_vouchers.dart';
import 'package:motogo_app/features/booking/v2/booking_v2_parts.dart';
import 'package:motogo_app/features/booking/v2/sections/extras_rows_v2.dart';
import 'package:motogo_app/features/booking/v2/sections/promo_v2.dart';
import 'package:motogo_app/features/booking/widgets/address_quick_options.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_booking.dart';
import '../support/v2_harness.dart';

const _gear = {
  ...kProfileOk,
  'gear_sizes': {
    'rider': {'helmet': 'M', 'boots': '43'},
    'passenger': {'helmet': 'L', 'gloves': 'M', 'jacket': 'XL', 'pants': 'L', 'boots': '39'},
  },
};

Future<ProviderContainer> _pump(WidgetTester t, List<Override> overrides, {List<MyVoucher> vouchers = const []}) async {
  t.view.physicalSize = const Size(412, 915) * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final router = GoRouter(initialLocation: '/booking', routes: [
    GoRoute(path: '/booking', builder: (_, __) => const Scaffold(body: BookingDebugWrapper())),
  ]);
  final c = ProviderContainer(overrides: [
    rankTokensProvider.overrideWithValue(RankTokens.forLevel(3)),
    rankArcPctProvider.overrideWithValue(50),
    myVouchersProvider.overrideWith((ref) async => vouchers),
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
        child: MediaQuery(
            data: MediaQuery.of(ctx).copyWith(disableAnimations: true, textScaler: TextScaler.noScaling), child: child!),
      ),
    ),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
  return c;
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f, warnIfMissed: false);
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

BookingDraft _d(ProviderContainer c) => c.read(bookingDraftProvider);
Finder _extraRow(int i) => find.byType(BookingExtraRowV2).at(i); // 0 passenger, 1 rider boots

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

  testWidgets('return "na adresu" takes the pickup address + price, shown answered', (t) async {
    final c = await _pump(
        t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw, pickupMethod: 'delivery'), pickupFee: 1200, pickupKm: 25));
    await _tap(t, find.byType(BkOptionRow).at(3)); // return: delivery
    final d = _d(c);
    expect([d.returnMethod, d.returnCity, d.returnAddress], ['delivery', 'Jihlava', 'Masarykovo náměstí 1']);
    expect([c.read(returnDelivFeeProvider), c.read(returnDistKmProvider)], [1200, 25]);
    expect(find.text('Stejná jako u přistavení'), findsOneWidget);
    expect(find.text('Změnit'), findsNWidgets(3)); // dates + both addresses
  });

  testWidgets('address sheet: other side + profile address in one tap', (t) async {
    final c = await _pump(t,
        bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw, pickupMethod: 'delivery', returnMethod: 'delivery')));
    await _tap(t, find.text('Zadej adresu'));
    final quick = find.byType(AddressQuickOptions);
    expect(quick, findsOneWidget);
    expect(find.descendant(of: quick, matching: find.text('Stejná jako u přistavení')), findsOneWidget);
    expect(find.descendant(of: quick, matching: find.text('Moje adresa z profilu')), findsOneWidget);
    expect(find.descendant(of: quick, matching: find.text('Mezná 9, 39301 Pelhřimov')), findsOneWidget);
    await _tap(t, find.text('Moje adresa z profilu'));
    await t.pump(const Duration(seconds: 1));
    expect(quick, findsNothing); // picked → distance shown, options hidden
    await _tap(t, find.text('POTVRDIT ADRESU'));
    final d = _d(c);
    expect([d.returnCity, d.returnAddress, d.pickupCity], ['Pelhřimov', 'Mezná 9', 'Jihlava']);
    expect(c.read(returnDelivFeeProvider), greaterThan(0));
  });

  testWidgets('passenger sizes prefilled from the last booking; chosen → reopens + Odebrat', (t) async {
    final c = await _pump(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw), profile: _gear));
    await _tap(t, _extraRow(0));
    expect(find.textContaining('Velikosti jsme předvyplnili'), findsOneWidget);
    expect(find.text('Odebrat'), findsNothing);
    await _tap(t, find.text('POTVRDIT'));
    var p = _d(c).extras.singleWhere((e) => e.id == 'extra-spolujezdec');
    expect(p.size, 'Helma: L, Rukavice: M, Bunda: XL, Kalhoty: L');
    // Tap the chosen extra: same sizes come back (not removed any more).
    await _tap(t, _extraRow(0));
    expect(find.textContaining('Velikosti jsme předvyplnili'), findsNothing);
    await _tap(t, find.text('POTVRDIT'));
    p = _d(c).extras.singleWhere((e) => e.id == 'extra-spolujezdec');
    expect(p.size, 'Helma: L, Rukavice: M, Bunda: XL, Kalhoty: L');
    await _tap(t, _extraRow(0));
    await _tap(t, find.text('Odebrat'));
    expect(_d(c).extras.where((e) => e.id == 'extra-spolujezdec'), isEmpty);
  });

  testWidgets('boots: last size marked "naposledy" but never chosen without a tap', (t) async {
    final c = await _pump(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw), profile: _gear));
    await _tap(t, _extraRow(1));
    expect(find.text('naposledy'), findsOneWidget);
    expect(_d(c).extras, isEmpty);
    await _tap(t, find.text('43'));
    expect(_d(c).extras.single.size, '43');
    await _tap(t, _extraRow(1));
    expect(find.text('naposledy'), findsNothing);
    await _tap(t, find.text('Odebrat'));
    expect(_d(c).extras, isEmpty);
  });

  testWidgets('own vouchers: chips in the card (minus applied), tap = the same code check', (t) async {
    final applied = [AppliedDiscount(code: 'DAR500', type: DiscountType.fixed, value: 500, isVoucher: true)];
    await _pump(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw, discounts: applied)),
        vouchers: const [MyVoucher(code: 'DAR1000', amount: 1000), MyVoucher(code: 'DAR500', amount: 500)]);
    final card = find.byType(BookingPromoV2);
    expect(find.descendant(of: card, matching: find.textContaining('DAR1000')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.textContaining('DAR500 ·')), findsNothing);
    await _tap(t, find.descendant(of: card, matching: find.textContaining('DAR1000')));
    await t.pump(const Duration(seconds: 1));
    expect(find.byType(AlertDialog), findsOneWidget);
    final field = t.widget<TextField>(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)));
    expect(field.controller!.text, 'DAR1000');
    // No backend in tests → the existing check answers with its reason.
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.byType(CircularProgressIndicator)), findsNothing);
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.byType(MyVoucherChips)), findsOneWidget);
  });
}
