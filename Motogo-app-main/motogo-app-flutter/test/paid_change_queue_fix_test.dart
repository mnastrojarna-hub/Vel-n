// Fronta zaplacených změn (D6) — opravy po kontrole 2026-10-16:
//  • návrat z banky po 3D Secure (popředí = drain force) nesmí sáhnout na
//    nezaplacenou pojistku před jejím časem,
//  • po zápisu změny serverem appka dopíše velikosti výbavy / vlastní výbavu
//    (nejsou ve Stripe metadatech) — idempotentně, při chybě znovu,
//  • platba jiného účtu / nedohledatelná: konečný stav, žádné „dokončuje se" 7 dní.
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/paid_change_apply.dart';
import 'package:motogo_app/core/paid_change_queue.dart';
import 'package:motogo_app/features/payment/paid_change_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late DateTime now;
  late List<CompleteResponse> answers;
  late List<String> calls;
  late List<Map<String, dynamic>> gearWrites;
  late bool gearOk;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PaidChangeQueue.resetForTest();
    PaidChangeQueue.autoSchedule = false;
    now = DateTime(2026, 10, 16, 12);
    PaidChangeQueue.clock = () => now;
    answers = [];
    calls = [];
    gearWrites = [];
    gearOk = true;
    PaidChangeApply.complete = (pi, _) async {
      calls.add(pi);
      return answers.isEmpty ? const CompleteResponse(CompleteState.retry) : answers.removeAt(0);
    };
    PaidChangeApply.applyExtras = (_, __) async => true;
    PaidChangeApply.clientApply = (_) async => true;
    PaidChangeApply.applyGear = (_, g) async {
      gearWrites.add(g);
      return gearOk;
    };
  });

  test('forced drain (resume after 3D Secure) skips the unpaid entry until it is due', () async {
    await PaidChangeQueue.enqueue(
        const PaidChangeEntry(key: 'pi_a', bookingId: 'b', kind: 'edit', charge: 15, paid: false),
        delay: const Duration(seconds: 90));
    await PaidChangeQueue.enqueue(const PaidChangeEntry(key: 'pi_b', bookingId: 'b', kind: 'edit', charge: 15));
    await PaidChangeQueue.drain(reason: 'resume', force: true);
    expect(calls, ['pi_b'], reason: 'zaplacená položka hned, nezaplacená čeká');
    expect(await PaidChangeQueue.get('pi_a'), isNotNull);
  });

  test('server applied → gear sizes and own_gear are written (only those columns)', () async {
    await PaidChangeQueue.enqueue(const PaidChangeEntry(key: 'pi_g', bookingId: 'b1', kind: 'edit', charge: 690,
        columns: {
          'end_date': '2026-11-02',
          'total_price': 5690,
          'passenger_helmet_size': 'M',
          'passenger_boots_size': '43',
          'own_gear': false,
          'modification_history': [],
        }));
    answers.add(const CompleteResponse(CompleteState.applied));
    await PaidChangeQueue.drain(reason: 'test');
    expect(gearWrites.single, {'passenger_helmet_size': 'M', 'passenger_boots_size': '43', 'own_gear': false});
    expect(await PaidChangeQueue.all(), isEmpty);
  });

  test('gear write failed → retried later without asking the server again', () async {
    await PaidChangeQueue.enqueue(const PaidChangeEntry(key: 'pi_h', bookingId: 'b1', kind: 'edit', charge: 15,
        columns: {'helmet_size': 'L'}));
    answers.add(const CompleteResponse(CompleteState.applied));
    gearOk = false;
    await PaidChangeQueue.drain(reason: 'test');
    expect((await PaidChangeQueue.get('pi_h'))!.state, 'extras');
    calls.clear();
    gearOk = true;
    await PaidChangeQueue.drain(reason: 'test', force: true);
    expect(calls, isEmpty);
    expect(gearWrites, hasLength(2));
    expect(await PaidChangeQueue.all(), isEmpty);
  });

  test('legacy client apply writes all columns itself → no separate gear write', () async {
    await PaidChangeQueue.enqueue(const PaidChangeEntry(key: 'pi_c', bookingId: 'b1', kind: 'edit', charge: 15,
        columns: {'helmet_size': 'L'}));
    answers.add(const CompleteResponse(CompleteState.clientApply));
    await PaidChangeQueue.drain(reason: 'test');
    expect(gearWrites, isEmpty);
  });

  test('gear columns are picked from the change only', () {
    expect(gearColumnsOf({'total_price': 1, 'end_date': 'x'}), isNull);
    expect(gearColumnsOf({'gloves_size': null, 'start_date': 'x'}), {'gloves_size': null});
  });

  test('403 / 404 / 409 from complete_extension are terminal (with the server code)', () {
    CompleteResponse r(int s, String code) => CompleteResponse.fromHttp(s, {'success': false, 'code': code});
    expect(r(403, 'forbidden').state, CompleteState.failed);
    expect(r(403, 'forbidden').reason, 'other_account');
    expect(r(404, 'not_found').reason, 'gone');
    expect(r(409, 'not_extension').reason, 'gone');
    expect(r(404, 'not_found').refund, 'none');
    // Holá 404 brány (funkce se právě nasazuje) → zkusit znovu.
    expect(CompleteResponse.fromHttp(404, null).state, CompleteState.retry);
    expect(CompleteResponse.fromHttp(409, {'code': 'stale_booking'}).state, CompleteState.retry);
  });

  test('paid entry + other account → failed once; unpaid safety entry → removed silently', () async {
    await PaidChangeQueue.enqueue(const PaidChangeEntry(key: 'pi_p', bookingId: 'b', kind: 'swap', charge: 15));
    await PaidChangeQueue.enqueue(const PaidChangeEntry(key: 'pi_u', bookingId: 'b', kind: 'swap', charge: 15, paid: false));
    answers
      ..add(const CompleteResponse(CompleteState.failed, reason: 'other_account', refund: 'none'))
      ..add(const CompleteResponse(CompleteState.failed, reason: 'gone', refund: 'none'));
    await PaidChangeQueue.drain(reason: 'test');
    expect((await PaidChangeQueue.get('pi_p'))!.failure?['reason'], 'other_account');
    expect(await PaidChangeQueue.get('pi_u'), isNull);
    // Selhání se už nezkouší znovu.
    calls.clear();
    await PaidChangeQueue.drain(reason: 'test', force: true);
    expect(calls, isEmpty);
  });
}
