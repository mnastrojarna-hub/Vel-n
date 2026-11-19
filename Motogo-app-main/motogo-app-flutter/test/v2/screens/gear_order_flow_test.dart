// 5.0.2 objednávka samotné výbavy (/gear-rental) v obou vzhledech:
// kroky webu → create_web_gear_booking (souhlasy, předvyplněný kontakt) →
// platební obrazovka s kontextem výpůjčky; děkovací stránka (zaplaceno +
// doklad totožnosti, čeká se) a vypnutá služba.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/features/auth/auth_provider.dart';
import 'package:motogo_app/features/gear_rental/gear_contract.dart';
import 'package:motogo_app/features/gear_rental/gear_done_screen.dart';
import 'package:motogo_app/features/gear_rental/gear_offer_provider.dart';
import 'package:motogo_app/features/gear_rental/gear_order_api.dart';
import 'package:motogo_app/features/gear_rental/gear_order_screen.dart';
import 'package:motogo_app/features/gear_rental/gear_order_state.dart';
import 'package:motogo_app/features/gear_rental/gear_quote.dart';
import 'package:motogo_app/features/payment/payment_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/v2_harness.dart';

class _Api extends GearOrderApi {
  final creates = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> rpc(String fn, Map<String, dynamic> p) async {
    if (fn == 'create_web_gear_booking') {
      creates.add(p);
      return {'success': true, 'booking_id': 'b-1', 'amount': 240, 'total': 240};
    }
    if (fn == 'quote_gear_booking') return {'success': true, 'per_day': 120, 'amount': 240};
    return {'enabled': false};
  }
}

final _today = DateTime(2026, 11, 19);
GearOrderData _data({bool enabled = true}) => GearOrderData(
      cfg: GearRentalSettings(enabled: enabled, appVisible: true),
      prices: const [
        GearPrice(key: 'set', kind: 'set', label: 'Komplet helma + rukavice', desc: 'Helma a rukavice', includes: ['helmet', 'gloves'], perDay: 150),
        GearPrice(key: 'helmet', kind: 'item', label: 'Helma', sizes: ['S', 'M', 'L'], perDay: 120),
        GearPrice(key: 'gloves', kind: 'item', label: 'Rukavice', sizes: ['S', 'M', 'L'], perDay: 50),
      ],
      branches: const [GearBranch(id: 'm', name: 'Mezná', address: 'Mezná 9, Mezná'), GearBranch(id: 'v', name: 'Velké Němčice', self: true)],
      closures: const [],
      today: _today,
    );

final _shot = GlobalKey();

Future<ProviderContainer> _pump(WidgetTester tester, Widget screen,
    {required bool v2, List<Override> overrides = const [], Size size = const Size(360, 780), String lang = 'cs'}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final router = GoRouter(initialLocation: '/gear', routes: [
    GoRoute(path: '/gear', builder: (_, __) => Scaffold(body: screen)),
    GoRoute(path: '/payment', builder: (_, __) => const Scaffold(body: Text('PAYMENT'))),
    GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('HOME'))),
    GoRoute(path: '/reservations/:id', builder: (_, s) => Scaffold(body: Text('RES ${s.pathParameters['id']}'))),
  ]);
  final scope = RepaintBoundary(key: _shot, child: ProviderScope(
    overrides: [
      rankTokensProvider.overrideWithValue(RankTokens.forLevel(3)),
      rankArcPctProvider.overrideWithValue(50),
      profileProvider.overrideWith((ref) async => {'full_name': 'Jan Novák', 'phone': '777111222', 'city': 'Brno'}),
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
      theme: v2 ? v2TestTheme() : legacyTestTheme(),
      builder: (c, child) => MgV2Scope(
        enabled: v2,
        child: MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.noScaling, disableAnimations: true),
          child: child!,
        ),
      ),
    ),
  ));
  await tester.pumpWidget(scope);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp).first));
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  // Do středu obrazovky — u v2 by spodní okraj překryl dok s tlačítkem.
  await Scrollable.ensureVisible(tester.element(f), alignment: 0.4);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(f, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 450));
}

Future<void> _orderFlow(WidgetTester tester, {required bool v2}) async {
  final api = _Api();
  final c = await _pump(tester, const GearOrderScreen(), v2: v2, overrides: [
    gearOrderDataProvider.overrideWith((ref) async => _data()),
    gearOrderApiProvider.overrideWithValue(api),
    gearOrderUserProvider.overrideWithValue(('u1', 'jan@example.cz')),
  ]);
  expect(find.text('Kde si výbavu vyzvedneš'), findsOneWidget);
  expect(find.text('Přihlášen(a) jako jan@example.cz'), findsOneWidget);
  await _tap(tester, find.byKey(const ValueKey('gear-branch-m')));
  final ctrl = c.read(gearOrderProvider.notifier);
  if (v2) {
    ctrl.tapDay(DateTime(2026, 11, 20));
    ctrl.tapDay(DateTime(2026, 11, 21));
    await tester.pump(const Duration(milliseconds: 450));
  } else {
    await _tap(tester, find.byKey(const ValueKey('gear-day-2026-11-20')));
    await _tap(tester, find.byKey(const ValueKey('gear-day-2026-11-21')));
  }
  expect(c.read(gearOrderProvider).nDays, 2);
  await _tap(tester, find.byKey(const ValueKey('gear-set-set')));
  await _tap(tester, find.byKey(const ValueKey('gear-size-helmet-M')));
  await _tap(tester, find.byKey(const ValueKey('gear-size-gloves-L')));
  expect(c.read(gearOrderProvider).complete, isTrue);
  // CTA bez souhlasů → chyba webu, nic se nezakládá
  await _tap(tester, find.byKey(const ValueKey('gear-cta')));
  expect(api.creates, isEmpty);
  expect(find.text('Pro pokračování potvrď souhlas s podmínkami.'), findsWidgets);
  await _tap(tester, find.byKey(const ValueKey('gear-vop')));
  await _tap(tester, find.byKey(const ValueKey('gear-gdpr')));
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byKey(const ValueKey('gear-summary')), findsOneWidget);
  await _tap(tester, find.byKey(const ValueKey('gear-cta')));
  await tester.pump(const Duration(milliseconds: 300));
  final p = api.creates.single;
  expect(p['p_items'], [
    {'key': 'helmet', 'size': 'M'},
    {'key': 'gloves', 'size': 'L'},
  ]);
  expect(p['p_customer']['name'], 'Jan Novák');
  expect(p['p_customer']['email'], 'jan@example.cz');
  expect(p['p_consents'], {'vop': true, 'gdpr': true});
  expect(p['p_pickup_time'], '09:00');
  final pc = c.read(paymentContextProvider)!;
  expect(pc.bookingId, 'b-1');
  expect(pc.amount, 240);
  expect(pc.flowType, PaymentFlowType.booking);
  expect(pc.label, 'Výpůjčka výbavy');
  // Platba ví, že jde o výbavu (4h webové okno, bez rušení řádku appkou).
  expect(pc.gear, isTrue);
  expect(pc.bookingCreatedAt, isNotNull);
  expect(c.read(gearPaymentIdsProvider), contains('b-1'));
  expect(find.text('PAYMENT'), findsOneWidget);
  expect(tester.takeException(), isNull);
}

Map<String, dynamic> _paidJson({bool docs = true, bool self = true}) => {
      'id': 'b-1',
      'booking_kind': 'gear',
      'booking_number': 'ABCD1234',
      'status': 'reserved',
      'payment_status': 'paid',
      'start_date': '2026-11-20',
      'end_date': '2026-11-21',
      'days': 2,
      'pickup_time': self ? null : '09:00:00',
      'branch': {'name': 'MotoGo24 Velké Němčice', 'address': 'Hlavní 1', 'city': 'Velké Němčice', 'type': self ? 'samoobslužná' : 'obslužná'},
      'lines': [
        {'key': 'set', 'kind': 'set', 'label': 'Komplet', 'includes': ['helmet', 'gloves'], 'sizes': {'helmet': 'M', 'gloves': 'L'}},
      ],
      'per_day': 150,
      'subtotal': 300,
      'total': 300,
      'voucher_amount': 0,
      'docs': {'required': true, 'ok': !docs},
    };

void main() {
  setUpAll(loadMontserrat);

  testWidgets('v2: steps → create (consents, profile contact) → payment with gear context', (tester) async {
    await _orderFlow(tester, v2: true);
  });

  testWidgets('old look: steps → create → payment', (tester) async {
    await _orderFlow(tester, v2: false);
  });

  testWidgets('service off → web text, no form', (tester) async {
    await _pump(tester, const GearOrderScreen(), v2: true, overrides: [
      gearOrderDataProvider.overrideWith((ref) async => _data(enabled: false)),
      gearOrderUserProvider.overrideWithValue(('u1', 'jan@example.cz')),
    ]);
    expect(find.byKey(const ValueKey('gear-order-message')), findsOneWidget);
    expect(find.textContaining('pozastavené'), findsOneWidget);
  });

  for (final v2 in [true, false]) {
    testWidgets('done (${v2 ? 'v2' : 'old'}): paid + ID document card + next steps + buttons', (tester) async {
      await _pump(tester, const GearDoneScreen(bookingId: 'b-1'), v2: v2, overrides: [
        gearDoneFetchProvider.overrideWithValue((id) async => _paidJson()),
        gearPricesProvider.overrideWith((ref) async => _data().prices),
        gearOrderUserProvider.overrideWithValue(('u1', 'jan@example.cz')),
      ]);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Hotovo, výbava je tvoje!'), findsOneWidget);
      expect(find.text('ABCD1234'), findsWidgets);
      expect(find.byKey(const ValueKey('gear-done-docs')), findsOneWidget);
      expect(find.byKey(const ValueKey('gear-done-next')), findsOneWidget);
      expect(find.textContaining('helma M, rukavice L'), findsOneWidget);
      final show = find.byWidgetPredicate(
          (w) => w is Text && (w.data ?? w.textSpan?.toPlainText() ?? '').toLowerCase() == 'zobrazit rezervaci');
      expect(show, findsOneWidget);
      await _tap(tester, show);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('RES b-1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('done: unpaid after polling → pending text', (tester) async {
    await _pump(tester, const GearDoneScreen(bookingId: 'b-1', pollEvery: Duration(milliseconds: 10)), v2: true, overrides: [
      gearDoneFetchProvider.overrideWithValue((id) async => {..._paidJson(), 'payment_status': 'unpaid'}),
      gearPricesProvider.overrideWith((ref) async => _data().prices),
    ]);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byKey(const ValueKey('gear-done-pending')), findsOneWidget);
    expect(find.textContaining('Platba se ještě zpracovává'), findsOneWidget);
  });

  for (final v2 in [true, false]) {
    for (final (lang, size) in [('cs', const Size(320, 640)), ('de', const Size(360, 780))]) {
      testWidgets('fit ${v2 ? 'v2' : 'old'} $lang ${size.width.toInt()}: every section open, no overflow', (tester) async {
        final c = await _pump(tester, const GearOrderScreen(), v2: v2, size: size, lang: lang, overrides: [
          gearOrderDataProvider.overrideWith((ref) async => _data()),
          gearOrderApiProvider.overrideWithValue(_Api()),
          gearOrderUserProvider.overrideWithValue(('u1', 'jan.novak.s.dlouhym.emailem@example.cz')),
        ]);
        final ctrl = c.read(gearOrderProvider.notifier)
          ..setBranch('m')
          ..tapDay(DateTime(2026, 11, 20))
          ..tapDay(DateTime(2026, 11, 23))
          ..toggleSet('set')
          ..pickSize('helmet', 'M')
          ..setCompanyOn(true)
          ..setVoucherOn(true)
          ..applyVoucher('DAREK2026');
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 600));
        await maybeShot(tester, _shot, 'gear_order_${v2 ? 'v2' : 'old'}__${lang}__${size.width.toInt()}_top');
        for (final k in ['gear-step-items', 'gear-summary', 'gear-gdpr']) {
          final f = find.byKey(ValueKey(k));
          if (f.evaluate().isEmpty) continue;
          await Scrollable.ensureVisible(tester.element(f), alignment: 0.3);
          await tester.pump(const Duration(milliseconds: 300));
          await maybeShot(tester, _shot, 'gear_order_${v2 ? 'v2' : 'old'}__${lang}__${size.width.toInt()}_$k');
        }
        ctrl.setBranch('v');
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('shot: done v2 + old (paid, docs)', (tester) async {
    for (final v2 in [true, false]) {
      await _pump(tester, const GearDoneScreen(bookingId: 'b-1'), v2: v2, size: const Size(320, 640), overrides: [
        gearDoneFetchProvider.overrideWithValue((id) async => _paidJson()),
        gearPricesProvider.overrideWith((ref) async => _data().prices),
        gearOrderUserProvider.overrideWithValue(('u1', 'jan@example.cz')),
      ]);
      await tester.pump(const Duration(milliseconds: 600));
      await maybeShot(tester, _shot, 'gear_done_${v2 ? 'v2' : 'old'}__cs__320');
      expect(tester.takeException(), isNull);
    }
  });

  test('gear docs card shows only when required and not ok', () {
    expect(GearDoneInfo(_paidJson(), const []).docsNeeded, isTrue);
    expect(GearDoneInfo(_paidJson(docs: false), const []).docsNeeded, isFalse);
    expect(GearDoneInfo(_paidJson(), const []).branchLine, 'Velké Němčice, Hlavní 1, Velké Němčice');
    expect(gearDoneStage(GearDoneInfo(_paidJson(), const []), pending: false), GearDoneStage.paid);
    expect(gearDoneStage(null, pending: true), GearDoneStage.pending);
    expect(gearCountDays(_today, _today), 1);
  });
}
