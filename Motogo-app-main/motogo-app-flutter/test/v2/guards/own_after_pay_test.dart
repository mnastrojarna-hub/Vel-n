// D2 (owner 2026-11-14, P2-04 / M3-11): an unpaid booking gets its own
// "Zaplatit rezervaci · částka" on the list card and in the detail (new
// look) — shown exactly when the shell pay strip offers payment
// (`resPayTarget` = `resPayFlag` unpaid, the strip's provider) and doing
// exactly what the strip does (`openPendingPayment`, same booking). Every
// existing button stays, as secondary; the old look is unchanged.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/currency.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/core/router.dart';
import 'package:motogo_app/core/shell_fabs.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/payment/payment_provider.dart';
import 'package:motogo_app/features/reservations/reservation_models.dart';
import 'package:motogo_app/features/reservations/v2/res_detail_view_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_status_v2.dart';
import 'package:motogo_app/features/reservations/v2/reservation_card_v2.dart';
import 'package:motogo_app/features/reservations/v2/reservations_screen_v2.dart';
import 'package:motogo_app/features/reservations/widgets/res_detail_tab_content.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_reservations.dart';
import '../support/supabase_stub.dart';
import '../support/v2_harness.dart';

String _t(String key) => translations['cs']?[key] ?? key;
const _pay = ValueKey('res-pay-now');

PendingBooking _pending(Reservation r, {bool verifying = false, int ageMin = 5}) => PendingBooking(
    id: r.id,
    totalPrice: r.totalPrice,
    createdAt: DateTime.now().subtract(Duration(minutes: ageMin)),
    verifying: verifying);

Widget _detail(Reservation r) => ResDetailV2View(
      res: r,
      doorCodesAsync: const AsyncData([]),
      branchFullAddress: 'Boudky, Velké Němčice',
      onStaleRetry: null,
      onBack: () {},
      onShowCancelDialog: () {},
      onOpenFinalInvoice: (_, __) async {},
      onOpenContract: (_, __) async {},
      onRestoreBooking: (_, __) async {},
    );

Widget _oldDetail(Reservation r) => CustomScrollView(slivers: [
      ResDetailTabContent(
        res: r,
        doorCodesAsync: const AsyncData([]),
        statusColor: Colors.green,
        statusTitle: 'x',
        branchFullAddress: 'Boudky, Velké Němčice',
        onShowCancelDialog: () {},
        onOpenFinalInvoice: (_, __) async {},
        onOpenContract: (_, __) async {},
        onRestoreBooking: (_, __) async {},
      ),
    ]);

/// [child] at `/x` inside a real GoRouter (`/payment` = the target page).
Future<void> _pump(WidgetTester t, Widget child, List<Override> overrides, {bool v2 = true, double w = 360, String lang = 'cs'}) async {
  t.view.physicalSize = Size(w, 780) * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final router = GoRouter(initialLocation: '/x', routes: [
    GoRoute(path: '/x', builder: (_, __) => Scaffold(backgroundColor: const Color(0xFFF4F7F5), body: child)),
    GoRoute(path: Routes.payment, builder: (_, __) => const Scaffold(body: Text('PAYMENT PAGE'))),
  ]);
  await t.pumpWidget(ProviderScope(
    overrides: overrides,
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
      builder: (context, c) => MgV2Scope(
        enabled: v2,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling, disableAnimations: true),
          child: c!,
        ),
      ),
    ),
  ));
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _scrollTo(WidgetTester t, Finder f) async {
  await t.scrollUntilVisible(f, 250,
      scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first);
  await t.pump(const Duration(milliseconds: 300));
}

/// Taps [f] and returns what the tap set up: the route shown + the payment
/// context (flow, booking, amount, label, window start).
Future<List<Object?>> _tapTarget(WidgetTester t, Finder f) async {
  await t.tap(f);
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  final c = ProviderScope.containerOf(t.element(find.text('PAYMENT PAGE')));
  final p = c.read(paymentContextProvider)!;
  return [p.flowType, p.bookingId, p.amount, p.label, p.bookingCreatedAt];
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerReservationStrings();
    mockPathProvider();
    await stubSupabase();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MgMotion.resetSession();
  });

  // Created 5 min ago (as the journey state `unpaid_booking`): upcoming.
  final r = resv('u1', status: 'pending', pay: 'unpaid', from: 9, to: 11, self: false,
      created: DateTime.now().subtract(const Duration(minutes: 5)));

  group('resPayTarget = the strip\'s rule', () {
    test('only the unpaid, not verifying, not expired pending booking of THIS id', () {
      final p = _pending(r);
      expect(resPayTarget(r, p), same(p));
      expect(resPayTarget(r, null), isNull);
      expect(resPayTarget(r, _pending(r, verifying: true)), isNull);
      expect(resPayTarget(r, _pending(r, ageMin: 31)), isNull);
      expect(resPayTarget(resv('other', status: 'pending', pay: 'unpaid', from: 9, to: 11), p), isNull);
    });
  });

  testWidgets('card + detail + strip: one pay button each, the same payment target', (t) async {
    final p = _pending(r);
    final ov = resOverrides(pending: p);
    // The strip (shell, new look) — the reference target.
    await _pump(t, Align(alignment: Alignment.bottomCenter, child: ShellBookingFab(booking: p, v2: true)), ov);
    final strip = await _tapTarget(t, find.text(_t('coPayNowFab')));
    expect(strip, [PaymentFlowType.booking, r.id, r.totalPrice, _t('bookingReservation'), p.createdAt]);

    // List card: own CTA with the strip's text + amount; Detail / Upravit stay.
    await _pump(
        t,
        SingleChildScrollView(
            child: ReservationCardV2(
                reservation: r, onTap: () {}, onEdit: () {}, payFlag: resPayFlag(r, p), pay: resPayTarget(r, p))),
        ov);
    expect(find.byKey(_pay), findsOneWidget);
    expect(find.textContaining(_t('coPayNowFab').toUpperCase()), findsOneWidget);
    expect(find.textContaining(Money.czk(r.totalPrice).replaceAll(' ', ' ')), findsWidgets);
    expect(find.text(_t('detail')), findsOneWidget);
    expect(find.text(_t('edit')), findsOneWidget);
    expect(await _tapTarget(t, find.byKey(_pay)), strip);

    // Detail: own CTA above "Upravit rezervaci" (now outlined) + storno.
    await _pump(t, _detail(r), ov);
    await _scrollTo(t, find.byKey(_pay));
    expect(find.byKey(_pay), findsOneWidget);
    await _scrollTo(t, find.textContaining(_t('cancelReservationBtn')));
    expect(find.textContaining(_t('editReservation')), findsOneWidget);
    expect(t.getTopLeft(find.byKey(_pay)).dy, lessThan(t.getTopLeft(find.textContaining(_t('editReservation'))).dy));
    await _scrollTo(t, find.byKey(_pay));
    expect(await _tapTarget(t, find.byKey(_pay)), strip);
    expect(t.takeException(), isNull);
  });

  // SA-01: the real Moje rezervace list wires the card's pay button.
  for (final payable in [true, false]) {
    testWidgets('real list: pay button on the card ${payable ? "shown" : "absent without the strip"}', (t) async {
      await pumpV2(t, const ReservationsScreenV2(),
          size: const Size(360, 1600), overrides: resOverrides(list: [r], pending: payable ? _pending(r) : null));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(ReservationCardV2), findsOneWidget);
      expect(find.byKey(_pay), payable ? findsOneWidget : findsNothing);
      await t.pump(const Duration(seconds: 2));
    });
  }

  for (final c in <String, PendingBooking? Function(Reservation)>{
    'paid booking (no pending)': (_) => null,
    'payment being verified': (x) => _pending(x, verifying: true),
    'pay window expired': (x) => _pending(x, ageMin: 31),
  }.entries) {
    testWidgets('no pay button: ${c.key}', (t) async {
      final x = c.key.startsWith('paid') ? resv('u2', status: 'reserved', from: 9, to: 11, self: false) : r;
      final p = c.value(x);
      final ov = resOverrides(pending: p);
      await _pump(t, ReservationCardV2(reservation: x, onTap: () {}, onEdit: () {}, pay: resPayTarget(x, p)), ov);
      expect(find.byKey(_pay), findsNothing);
      await _pump(t, _detail(x), ov);
      await _scrollTo(t, find.textContaining(_t('cancelReservationBtn')));
      expect(find.byKey(_pay), findsNothing);
      // Without the pay button "Upravit rezervaci" stays the rank CTA (caps).
      expect(find.textContaining(_t('editReservation').toUpperCase()), findsOneWidget);
    });
  }

  testWidgets('old look: detail unchanged — no own pay button, same actions', (t) async {
    await _pump(t, _oldDetail(r), resOverrides(pending: _pending(r)), v2: false);
    await _scrollTo(t, find.textContaining(_t('cancelReservationBtn')));
    expect(find.byKey(_pay), findsNothing);
    expect(find.textContaining(_t('coPayNowFab')), findsNothing);
    expect(find.textContaining(_t('editReservation')), findsOneWidget);
  });

  testWidgets('de, 320 dp: the card with the pay button draws cleanly', (t) async {
    final p = _pending(r);
    final shot = GlobalKey();
    await _pump(
        t,
        SingleChildScrollView(child: RepaintBoundary(key: shot, child: ReservationCardV2(reservation: r, onTap: () {}, onEdit: () {}, payFlag: ResPayFlag.unpaid, pay: p))),
        resOverrides(pending: p),
        w: 320,
        lang: 'de');
    expect(find.textContaining(translations['de']!['coPayNowFab']!.toUpperCase()), findsOneWidget);
    expect(find.byKey(_pay), findsOneWidget);
    expect(t.takeException(), isNull);
    await maybeShot(t, shot, 'own_after_pay_card__de__320');
  });
}
