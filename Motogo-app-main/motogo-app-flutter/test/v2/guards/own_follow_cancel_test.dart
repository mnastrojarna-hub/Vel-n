// W-03 (own_follow F2): in the new look the storno dialog of a booking that
// was NEVER paid (the pay strip / "Zaplatit" rule `resPayTarget`) must not
// promise "Teď ti vrátíme … (100 %)": it says that nothing will be paid
// (`coCancelPendingBody`, the strip's own cancel text). Buttons, their
// actions and the cancel call (`cancel_booking_tracked`, id + reason) stay;
// a paid booking and the old look are unchanged.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motogo_app/core/currency.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/core/supabase_client.dart';
import 'package:motogo_app/features/reservations/reservation_models.dart';
import 'package:motogo_app/features/reservations/v2/res_cancel_v2.dart';
import 'package:motogo_app/features/reservations/widgets/res_cancel_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_reservations.dart';
import '../support/v2_harness.dart';

String _t(String key) => translations['cs']?[key] ?? key;

/// Every request the dialog sends (the cancel RPC answers success).
final _calls = <http.Request>[];

PendingBooking _pending(Reservation r) =>
    PendingBooking(id: r.id, totalPrice: r.totalPrice, createdAt: DateTime.now().subtract(const Duration(minutes: 5)));

String _refundNow(Reservation r) {
  final pct = StornoCalc.effectiveRefundPercent(r.startDate, r);
  final amount = StornoCalc.effectiveRefundAmount(r.totalPrice, r.startDate, r);
  return _t('v2UxRpRefundNow').replaceAll('{amount}', Money.czk(amount)).replaceAll('{pct}', '$pct');
}

String _oldRefund(Reservation r) => _t('currentlyRefund')
    .replaceAll('{pct}', '${StornoCalc.effectiveRefundPercent(r.startDate, r)}')
    .replaceAll('{amount}', StornoCalc.effectiveRefundAmount(r.totalPrice, r.startDate, r).toStringAsFixed(0));

Future<void> _open(WidgetTester t, Reservation r, PendingBooking? p, {bool v2 = true}) async {
  await pumpV2(
    t,
    Builder(
      builder: (c) => Center(
        child: TextButton(
          onPressed: () => showDialog(context: c, builder: (_) => ResCancelDialog(reservation: r)),
          child: const Text('OPEN'),
        ),
      ),
    ),
    v2: v2,
    overrides: resOverrides(list: [r], pending: p),
  );
  await t.tap(find.text('OPEN'));
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerReservationStrings();
    mockPathProvider();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: MotoGoSupabase.url,
      publishableKey: 'test-anon',
      httpClient: MockClient((req) async {
        _calls.add(req);
        final body = req.url.path.endsWith('/rpc/cancel_booking_tracked')
            ? '{"success":true,"refund_percent":0,"refund_amount":0}'
            : '[]';
        return http.Response(body, 200, headers: {'content-type': 'application/json'});
      }),
      authOptions: const FlutterAuthClientOptions(
          localStorage: EmptyLocalStorage(), detectSessionInUri: false, autoRefreshToken: false),
      debug: false,
    );
  });
  setUp(_calls.clear);

  // Starts in 9 days → 100 % band, whatever the weekday or hour.
  final unpaid = resv('u1', status: 'pending', pay: 'unpaid', from: 9, to: 11, self: false,
      created: DateTime.now().subtract(const Duration(minutes: 5)));
  final paid = resv('p1', status: 'reserved', from: 9, to: 11, self: false);

  testWidgets('new look, never paid: no refund promise, "nothing will be paid"; cancel = the same RPC', (t) async {
    await _open(t, unpaid, _pending(unpaid));
    final dlg = t.widget<ResCancelConfirmV2>(find.byType(ResCancelConfirmV2));
    expect(dlg.refundLine, _t('coCancelPendingBody'));
    expect(find.text(_t('coCancelPendingBody')), findsOneWidget);
    expect(find.text(_refundNow(unpaid)), findsNothing);
    expect(find.textContaining(Money.czk(unpaid.totalPrice)), findsNothing);
    // Buttons unchanged: keep (safe) + cancel (destructive).
    expect(find.text(_t('v2UxRpKeepRes')), findsOneWidget);
    await t.tap(find.text(_t('cancelReservationBtn')));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final rpc = _calls.where((c) => c.url.path.endsWith('/rest/v1/rpc/cancel_booking_tracked')).toList();
    expect(rpc, hasLength(1));
    final body = jsonDecode(rpc.single.body) as Map<String, dynamic>;
    expect(body['p_booking_id'], unpaid.id);
    expect(body.keys.toSet(), {'p_booking_id', 'p_reason'}, reason: 'no refund amount is sent by the app');
    expect(find.byType(ResCancelConfirmV2), findsNothing, reason: 'the same result step follows');
    expect(t.takeException(), isNull);
  });

  testWidgets('new look, keep the booking: closes, no call', (t) async {
    await _open(t, unpaid, _pending(unpaid));
    await t.tap(find.text(_t('v2UxRpKeepRes')));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(ResCancelConfirmV2), findsNothing);
    expect(_calls.where((c) => c.url.path.contains('cancel_booking')), isEmpty);
  });

  for (final c in <String, (Reservation, PendingBooking?)>{
    'paid booking': (paid, null),
    'unpaid booking without the pay strip (expired / other)': (unpaid, null),
    'payment being verified': (
      unpaid,
      PendingBooking(id: unpaid.id, totalPrice: unpaid.totalPrice, createdAt: DateTime.now(), verifying: true)
    ),
  }.entries) {
    testWidgets('new look, ${c.key}: the refund sentence exactly as before', (t) async {
      final (r, p) = c.value;
      await _open(t, r, p);
      expect(t.widget<ResCancelConfirmV2>(find.byType(ResCancelConfirmV2)).refundLine, _refundNow(r));
      expect(find.text(_refundNow(r)), findsOneWidget);
      expect(find.text(_t('coCancelPendingBody')), findsNothing);
    });
  }

  for (final r in [unpaid, paid]) {
    testWidgets('old look unchanged (${r.paymentStatus}): its refund line, no new text', (t) async {
      await _open(t, r, r == unpaid ? _pending(r) : null, v2: false);
      expect(find.byType(ResCancelConfirmV2), findsNothing);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(_oldRefund(r)), findsOneWidget);
      expect(find.text(_t('coCancelPendingBody')), findsNothing);
    });
  }
}
