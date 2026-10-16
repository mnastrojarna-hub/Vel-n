// Odpověď majitele 2026-10-16 (otázka 3) — appka zabitá během 3D Secure / před
// dokončením platby, zaplacenou výměnu po restartu dokončuje fronta a server ji
// odmítne (motorka je mezitím obsazená — nová rezervace má přednost, doplatek se
// vrací). PaymentIntent je i po vratce „succeeded", takže ověření platby podle
// značky NESMÍ ohlásit „Doplatek proběhl, výměnu dokončujeme" (fxSwapPaidNotice):
// po restartu se ukáže „Motorka je mezitím obsazená" + vratka a detail rezervace.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/paid_after_restart.dart';
import 'package:motogo_app/core/paid_change_apply.dart';
import 'package:motogo_app/core/paid_change_queue.dart';
import 'package:motogo_app/core/payment_pending_marker.dart';
import 'package:motogo_app/features/payment/card_minimum.dart' show kcExact;
import 'package:motogo_app/features/payment/paid_change_api.dart';
import 'package:motogo_app/features/payment/paid_change_outcomes.dart';
import 'package:motogo_app/features/payment/payment_verify.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _taken = CompleteResponse(CompleteState.failed, reason: 'new_moto_unavailable', refund: 'auto', amount: 15);

void main() {
  late List<CompleteResponse> answers;
  late int verifies;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PaidChangeQueue.resetForTest();
    PaidChangeQueue.autoSchedule = false;
    PaidChangeQueue.clock = DateTime.now;
    answers = [];
    verifies = 0;
    PaidChangeApply.complete =
        (_, __) async => answers.isEmpty ? const CompleteResponse(CompleteState.retry) : answers.removeAt(0);
    PaidChangeApply.applyExtras = (_, __) async => true;
    PaidChangeApply.clientApply = (_) async => true;
    PaidChangeApply.applyGear = (_, __) async => true;
    // PaymentIntent doplatku zůstává po vratce „succeeded" → ověření by řeklo „zaplaceno".
    PaidAfterRestartCheck.verify = (_) async {
      verifies++;
      return VerifyState.paid;
    };
  });

  Future<void> marker(String id, String kind) =>
      PaymentPendingMarker.set(id, clientSecret: 'pi_$id${kind}_secret_x', fresh: true, kind: kind);

  Future<String> snackText(WidgetTester tester, PaidAfterRestart paid) async {
    late AppTranslations tr;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) {
      tr = t(context);
      return TextButton(
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(paidAfterRestartSnackBar(context, paid)),
        child: const Text('go'),
      );
    }))));
    await tester.tap(find.text('go'));
    await tester.pump();
    final texts = tester.widgetList<Text>(find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)));
    expect(find.text(tr.tr('psShow')), findsOneWidget, reason: 'akce otevře detail rezervace');
    return texts.map((w) => w.data ?? '').join('\n');
  }

  test('queue result failed (bike taken) + marker present → failure notice, never "paid"', () async {
    await marker('b1', PaymentMarkerKind.swap);
    answers.add(_taken);
    final r = await PaidAfterRestartCheck.run();
    expect(r, isNotNull);
    expect(r!.failed, isTrue);
    expect(r.completing, isFalse);
    expect((r.bookingId, r.kind, r.reason, r.refund, r.amount), ('b1', PaymentMarkerKind.swap, 'new_moto_unavailable', 'auto', 15.0));
    expect(verifies, 0, reason: 'stav PaymentIntentu se po vratce neptá — lhal by');
    expect(await PaymentPendingMarker.isPending('b1'), isFalse, reason: 'značka je vyřízená');
    final kept = await PaidChangeQueue.forBooking('b1');
    expect(kept.single.isFailed, isTrue, reason: 'banner v detailu nabídne Vybrat jinou / Ponechat');
    expect(await PaidChangeQueue.all(), hasLength(1));
    // Další start: žádné opakované oznámení ani falešné „zaplaceno".
    expect(await PaidAfterRestartCheck.run(), isNull);
    expect(verifies, 0);
  });

  test('failure stored by an earlier run (drain skips it) + marker → failure notice', () async {
    await PaidChangeQueue.enqueue(const PaidChangeEntry(key: 'pi_b2swap', bookingId: 'b2', kind: 'swap', charge: 690));
    answers.add(const CompleteResponse(CompleteState.failed, reason: 'moto_unavailable', refund: 'staff'));
    await PaidChangeQueue.drain(reason: 'timer');
    await marker('b2', PaymentMarkerKind.swap);
    final r = await PaidAfterRestartCheck.run();
    expect(r?.failed, isTrue);
    expect((r!.reason, r.refund, r.amount), ('moto_unavailable', 'staff', 690.0));
    expect(verifies, 0);
  });

  test('change still completing + PI paid → "completing", not "saved"', () async {
    await marker('b3', PaymentMarkerKind.edit);
    answers.add(const CompleteResponse(CompleteState.pending));
    final r = await PaidAfterRestartCheck.run();
    expect(r?.failed, isFalse);
    expect(r?.completing, isTrue);
    expect(r?.kind, PaymentMarkerKind.edit);
  });

  test('applied now → the usual success notice (unchanged)', () async {
    await marker('b4', PaymentMarkerKind.swap);
    answers.add(const CompleteResponse(CompleteState.applied));
    final r = await PaidAfterRestartCheck.run();
    expect((r?.failed, r?.completing, r?.kind), (false, false, PaymentMarkerKind.swap));
    expect(await PaymentPendingMarker.isPending('b4'), isFalse);
    expect(verifies, 0);
  });

  testWidgets('snackbar: taken → "booked in the meantime" + refund, no fxSwapPaidNotice', (tester) async {
    final text = await snackText(tester, const PaidAfterRestart('b1', PaymentMarkerKind.swap,
        failed: true, reason: 'new_moto_unavailable', refund: 'auto', amount: 15));
    final tr = AppTranslations.of('en');
    expect(text, contains(tr.tr('pdTakenTitle')));
    expect(text, contains(tr.tr('pdFailTaken')));
    expect(text, contains(tr.tr('pdRefundAuto').replaceAll('{amount}', kcExact(15))));
    expect(text, isNot(contains(tr.tr('fxSwapPaidNotice'))));
  });

  testWidgets('snackbar: other failure → swap failed title; completing edit → completing text', (tester) async {
    final tr = AppTranslations.of('en');
    final failed = await snackText(tester, const PaidAfterRestart('b1', PaymentMarkerKind.swap,
        failed: true, reason: 'swap_date_out_of_range', amount: 15));
    expect(failed, contains(tr.tr('pdSwapFailedTitle')));
    final busy = await snackText(tester, const PaidAfterRestart('b3', PaymentMarkerKind.edit, completing: true));
    expect(busy, tr.tr('pdEditCompletingShort'));
    final paid = await snackText(tester, const PaidAfterRestart('b4', PaymentMarkerKind.swap));
    expect(paid, tr.tr('fxSwapPaidNotice'));
  });
}
