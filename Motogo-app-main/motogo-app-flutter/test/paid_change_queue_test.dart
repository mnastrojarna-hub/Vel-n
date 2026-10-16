// Trvalá fronta zaplacených výměn / úprav (D6): zapsaná položka přežije
// restart, zkouší se s rostoucí prodlevou, dokud server zápis nepotvrdí;
// nezaplacené / trvale neproveditelné se uklidí, doplňky se nikdy nezdvojí.
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/paid_change_apply.dart';
import 'package:motogo_app/core/paid_change_queue.dart';
import 'package:motogo_app/features/payment/paid_change_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

PaidChangeEntry _e(String key, {bool paid = true, Map<String, dynamic>? extras, String kind = 'swap'}) =>
    PaidChangeEntry(key: key, bookingId: 'b-$key', kind: kind, charge: 15, paid: paid, extras: extras);

void main() {
  late DateTime now;
  late List<CompleteResponse> answers;
  late List<String> calls;
  late int extrasCalls;
  late bool extrasOk;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PaidChangeQueue.resetForTest();
    PaidChangeQueue.autoSchedule = false;
    now = DateTime(2026, 10, 16, 12);
    PaidChangeQueue.clock = () => now;
    answers = [];
    calls = [];
    extrasCalls = 0;
    extrasOk = true;
    PaidChangeApply.complete = (pi, _) async {
      calls.add(pi);
      return answers.isEmpty ? const CompleteResponse(CompleteState.retry) : answers.removeAt(0);
    };
    PaidChangeApply.applyExtras = (_, __) async {
      extrasCalls++;
      return extrasOk;
    };
    PaidChangeApply.clientApply = (_) async => true;
  });

  test('enqueue is idempotent and survives a "restart" (persisted)', () async {
    await PaidChangeQueue.enqueue(_e('pi_1', paid: false), delay: const Duration(seconds: 90));
    await PaidChangeQueue.enqueue(_e('pi_1'));
    PaidChangeQueue.resetForTest(); // „restart" — stav jen v úložišti
    final all = await PaidChangeQueue.all();
    expect(all, hasLength(1));
    expect(all.single.paid, isTrue, reason: 'paid se jen zapíná');
    expect(all.single.nextAt, now.millisecondsSinceEpoch, reason: 'zaplaceno → zkusit hned');
  });

  test('applied → removed and "done" event', () async {
    await PaidChangeQueue.enqueue(_e('pi_2'));
    answers.add(const CompleteResponse(CompleteState.applied));
    final events = <PaidChangeEvent>[];
    final sub = PaidChangeQueue.events.listen(events.add);
    await PaidChangeQueue.drain(reason: 'test');
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(await PaidChangeQueue.all(), isEmpty);
    expect(events.single.result.status, PaidChangeStatus.done);
    expect(calls, ['pi_2']);
  });

  test('retry / offline → backoff 10 s, 30 s, 1 min … then every 10 min', () async {
    await PaidChangeQueue.enqueue(_e('pi_3'));
    final waits = <int>[];
    for (var i = 0; i < 8; i++) {
      answers.add(const CompleteResponse(CompleteState.retry, offline: true));
      await PaidChangeQueue.drain(reason: 'test', force: true);
      final e = (await PaidChangeQueue.get('pi_3'))!;
      waits.add((e.nextAt - now.millisecondsSinceEpoch) ~/ 1000);
    }
    expect(waits, [10, 30, 60, 120, 300, 600, 600, 600]);
  });

  test('not due yet → drain skips it (unless forced)', () async {
    await PaidChangeQueue.enqueue(_e('pi_4', paid: false), delay: const Duration(seconds: 90));
    await PaidChangeQueue.drain(reason: 'test');
    expect(calls, isEmpty);
    now = now.add(const Duration(seconds: 91));
    await PaidChangeQueue.drain(reason: 'test');
    expect(calls, ['pi_4']);
  });

  test('not paid → removed silently; failed → kept once for the UI, then acknowledged', () async {
    await PaidChangeQueue.enqueue(_e('pi_5'));
    await PaidChangeQueue.enqueue(_e('pi_6'));
    answers
      ..add(const CompleteResponse(CompleteState.notPaid))
      ..add(const CompleteResponse(CompleteState.failed, reason: 'new_moto_unavailable', refund: 'auto', amount: 15));
    await PaidChangeQueue.drain(reason: 'test');
    expect(await PaidChangeQueue.get('pi_5'), isNull);
    final failed = (await PaidChangeQueue.get('pi_6'))!;
    expect(failed.isFailed, isTrue);
    expect(failed.failure?['reason'], 'new_moto_unavailable');
    // Selhaná položka se už neposílá znovu.
    calls.clear();
    await PaidChangeQueue.drain(reason: 'test', force: true);
    expect(calls, isEmpty);
    final r = await PaidChangeQueue.completeNow('pi_6');
    expect(r.status, PaidChangeStatus.failed);
    await PaidChangeQueue.acknowledge('pi_6');
    expect(await PaidChangeQueue.all(), isEmpty);
  });

  test('extras: server applied but extras failed → only extras are retried', () async {
    await PaidChangeQueue.enqueue(_e('pi_7', kind: 'edit', extras: {'rows': [], 'del': [], 'orig': []}));
    answers.add(const CompleteResponse(CompleteState.applied));
    extrasOk = false;
    await PaidChangeQueue.drain(reason: 'test');
    final e = (await PaidChangeQueue.get('pi_7'))!;
    expect(e.state, 'extras');
    calls.clear();
    extrasOk = true;
    await PaidChangeQueue.drain(reason: 'test', force: true);
    expect(calls, isEmpty, reason: 'server se už neptá, jen doplňky');
    expect(extrasCalls, 2);
    expect(await PaidChangeQueue.all(), isEmpty);
  });

  test('single flight: concurrent drain + completeNow call the server once', () async {
    await PaidChangeQueue.enqueue(_e('pi_8'));
    PaidChangeApply.complete = (pi, _) async {
      calls.add(pi);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return const CompleteResponse(CompleteState.applied);
    };
    final a = PaidChangeQueue.drain(reason: 'a');
    final b = PaidChangeQueue.drain(reason: 'b');
    final c = PaidChangeQueue.completeNow('pi_8');
    await Future.wait([a, b, c]);
    expect(calls, ['pi_8']);
    expect(await PaidChangeQueue.all(), isEmpty);
  });

  test('discard removes only unpaid safety entries', () async {
    await PaidChangeQueue.enqueue(_e('pi_9', paid: false));
    await PaidChangeQueue.enqueue(_e('pi_10'));
    await PaidChangeQueue.discard('pi_9');
    await PaidChangeQueue.discard('pi_10');
    expect((await PaidChangeQueue.all()).map((e) => e.key), ['pi_10']);
    expect((await PaidChangeQueue.forBooking('b-pi_10')).single.key, 'pi_10');
  });

  test('entries older than 7 days expire', () async {
    await PaidChangeQueue.enqueue(_e('pi_11'));
    now = now.add(const Duration(days: 8));
    expect(await PaidChangeQueue.all(), isEmpty);
  });

  test('client_apply (payload not in metadata) → legacy client write, then done', () async {
    var client = 0;
    PaidChangeApply.clientApply = (_) async {
      client++;
      return true;
    };
    await PaidChangeQueue.enqueue(_e('pi_12', kind: 'edit'));
    answers.add(const CompleteResponse(CompleteState.clientApply));
    await PaidChangeQueue.drain(reason: 'test');
    expect(client, 1);
    expect(await PaidChangeQueue.all(), isEmpty);
  });
}
