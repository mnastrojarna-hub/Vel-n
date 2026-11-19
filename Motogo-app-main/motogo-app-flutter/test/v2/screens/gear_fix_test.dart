// 5.0.2 výpůjčka výbavy — regrese oprav po kontrole: poukaz ve starém
// vzhledu se skutečným motivem appky (MotoGoTheme), šířka vyprodaného čipu
// velikosti ve v2, platba výbavy s webovým oknem 4 h (bez rušení řádku appkou).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/features/auth/auth_provider.dart';
import 'package:motogo_app/features/gear_rental/gear_contract.dart';
import 'package:motogo_app/features/gear_rental/gear_offer_provider.dart';
import 'package:motogo_app/features/gear_rental/gear_order_api.dart';
import 'package:motogo_app/features/gear_rental/gear_order_screen.dart';
import 'package:motogo_app/features/gear_rental/gear_order_state.dart';
import 'package:motogo_app/features/gear_rental/v2/gear_items_v2.dart';
import 'package:motogo_app/features/payment/payment_provider.dart';
import 'package:motogo_app/features/payment/payment_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../render/cases_ux_pay_shop.dart' show psPayOverrides;
import '../support/fakes_booking.dart' show mockBookingPathProvider;
import '../support/ps_harness.dart';
import '../support/v2_harness.dart';

String _cs(String k) => AppTranslations.of('cs').tr(k);

/// Sklad: helma L vyprodaná (sledovaný druh), rukavice bez omezení.
class _Api extends GearOrderApi {
  @override
  Future<Map<String, dynamic>> rpc(String fn, Map<String, dynamic> p) async {
    if (fn == 'get_gear_rental_availability') {
      return {
        'enabled': true,
        'sizes': {
          'helmet': {'S': 2, 'M': 2, 'L': 0, 'XL': 1, '2XL': 1},
        },
      };
    }
    if (fn == 'quote_gear_booking') return {'success': true, 'per_day': 150, 'amount': 300};
    return {'enabled': false};
  }
}

GearOrderData _data() => GearOrderData(
      cfg: const GearRentalSettings(enabled: true, appVisible: true),
      prices: const [
        GearPrice(key: 'set', kind: 'set', label: 'Komplet', includes: ['helmet', 'gloves'], perDay: 150),
        GearPrice(key: 'helmet', kind: 'item', label: 'Helma', sizes: ['XS', 'S', 'M', 'L', 'XL', '2XL'], perDay: 120),
        GearPrice(key: 'gloves', kind: 'item', label: 'Rukavice', sizes: ['S', 'M', 'L'], perDay: 50),
      ],
      branches: const [GearBranch(id: 'm', name: 'Mezná', address: 'Mezná 9, Mezná')],
      closures: const [],
      today: DateTime(2026, 11, 19),
    );

/// Objednávka výbavy s daným motivem ([theme] null = v2 / jinak starý vzhled).
Future<ProviderContainer> _pumpOrder(WidgetTester tester, {required bool v2, required ThemeData theme}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(360, 780) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      rankTokensProvider.overrideWithValue(RankTokens.forLevel(3)),
      rankArcPctProvider.overrideWithValue(50),
      profileProvider.overrideWith((ref) async => {'full_name': 'Jan Novák', 'phone': '777111222'}),
      gearOrderDataProvider.overrideWith((ref) async => _data()),
      gearOrderApiProvider.overrideWithValue(_Api()),
      gearOrderUserProvider.overrideWithValue(('u1', 'jan@example.cz')),
    ],
    child: MaterialApp(
      locale: const Locale('cs'),
      supportedLocales: supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: theme,
      builder: (c, child) => MgV2Scope(
        enabled: v2,
        child: MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.noScaling, disableAnimations: true),
          child: child!,
        ),
      ),
      home: const Scaffold(body: GearOrderScreen()),
    ),
  ));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return ProviderScope.containerOf(tester.element(find.byType(GearOrderScreen)));
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await Scrollable.ensureVisible(tester.element(f), alignment: 0.4);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(f, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 450));
}

void main() {
  setUpAll(loadMontserrat);

  testWidgets('starý vzhled + motiv appky: „Mám dárkový poukaz“ ukáže pole i „Použít“ (bez pádu)', (tester) async {
    await _pumpOrder(tester, v2: false, theme: v2TestTheme()); // = MotoGoTheme.dark jako telefon
    await _tap(tester, find.byKey(const ValueKey('gear-voucher-on')));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('gear-voucher')), findsOneWidget);
    expect(find.byKey(const ValueKey('gear-voucher-apply')), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('gear-voucher-apply'))).width, lessThan(200));
  });

  testWidgets('v2: vyprodaná velikost drží šířku čipu (nerozbije mřížku)', (tester) async {
    final c = await _pumpOrder(tester, v2: true, theme: v2TestTheme());
    final ctrl = c.read(gearOrderProvider.notifier);
    ctrl.setBranch('m');
    ctrl.tapDay(DateTime(2026, 11, 20));
    ctrl.tapDay(DateTime(2026, 11, 21));
    ctrl.toggleItem('helmet', true);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    final out = find.byKey(const ValueKey('gear-size-helmet-L'));
    // XS chybí v mapě sledovaného druhu = vyprodaná (web), L má 0 kusů
    expect(find.byType(GearSizeOutChipV2), findsNWidgets(2));
    final w = tester.getSize(out).width;
    expect(w, lessThan(90));
    // stejná řada jako sousední volné velikosti
    expect(tester.getTopLeft(out).dy, tester.getTopLeft(find.byKey(const ValueKey('gear-size-helmet-M'))).dy);
    expect(tester.takeException(), isNull);
  });

  group('platba výbavy (PaymentScreen)', () {
    setUpAll(mockBookingPathProvider);

    PaymentContext ctx(DateTime createdAt) => PaymentContext(
          flowType: PaymentFlowType.booking,
          bookingId: 'gear-b-1',
          amount: 300,
          label: 'Výpůjčka výbavy',
          bookingCreatedAt: createdAt,
          gear: true,
        );

    testWidgets('odpočet = webové okno 4 h od vzniku (H:MM:SS), ne 30 min', (tester) async {
      final router = await pumpPs(tester, const PaymentScreen(),
          overrides: psPayOverrides(ctx: ctx(DateTime.now().subtract(const Duration(minutes: 10)))));
      expect(find.textContaining('Zbývá 3:4'), findsOneWidget);
      expect(find.textContaining('Zbývá 29:'), findsNothing);
      await psLeaveRoute(tester, router);
    });

    testWidgets('vypršení: text výbavy, žádné „motorku uvolnili“', (tester) async {
      final router = await pumpPs(tester, const PaymentScreen(),
          overrides: psPayOverrides(
              // hodiny testu neběží s falešným časem → okno už vypršelo
              ctx: ctx(DateTime.now().subtract(gearWebPaymentWindow).subtract(const Duration(seconds: 1)))));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text(_cs('gearPayExpiredBody')), findsOneWidget);
      expect(find.text(_cs('psExpiredBookingBody')), findsNothing);
      await psLeaveRoute(tester, router);
    });
  });
}
