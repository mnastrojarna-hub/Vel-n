// 5.0.2 výpůjčka jen výbavy — logika formuláře 1:1 jako web (submit.js,
// price.js, gear-rental.js): pořadí kontroly, parametry create_web_gear_booking
// (souhlasy, koncept), mapování chyb, kalendář, sklad, serverová cena, poukaz.
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/payment_pending_marker.dart';
import 'package:motogo_app/features/gear_rental/gear_contract.dart';
import 'package:motogo_app/features/gear_rental/gear_offer_provider.dart';
import 'package:motogo_app/features/gear_rental/gear_order_api.dart';
import 'package:motogo_app/features/gear_rental/gear_order_state.dart';
import 'package:motogo_app/features/gear_rental/gear_quote.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeApi extends GearOrderApi {
  final calls = <(String, Map<String, dynamic>)>[];
  Map<String, dynamic> Function(String fn, Map<String, dynamic> p) answer;
  FakeApi(this.answer);

  List<Map<String, dynamic>> of(String fn) => [for (final c in calls) if (c.$1 == fn) c.$2];

  @override
  Future<Map<String, dynamic>> rpc(String fn, Map<String, dynamic> params) async {
    calls.add((fn, params));
    return answer(fn, params);
  }
}

const _sizes = ['S', 'M', 'L', 'XL'];
final today = DateTime(2026, 11, 19);
GearOrderData data({bool selfOnly = false}) => GearOrderData(
      cfg: const GearRentalSettings(enabled: true, appVisible: true, selfServiceEnabled: true, maxDays: 5),
      prices: const [
        GearPrice(key: 'set', kind: 'set', label: 'Komplet', includes: ['helmet', 'gloves'], perDay: 150),
        GearPrice(key: 'helmet', kind: 'item', label: 'Helma', sizes: _sizes, perDay: 120),
        GearPrice(key: 'gloves', kind: 'item', label: 'Rukavice', sizes: _sizes, perDay: 50),
      ],
      branches: [
        if (!selfOnly) const GearBranch(id: 'm', name: 'Mezná', address: 'Mezná 9'),
        const GearBranch(id: 'v', name: 'Velké Němčice', self: true),
      ],
      closures: [GearClosure('m', DateTime(2026, 11, 25), DateTime(2026, 11, 26))],
      today: today,
    );

Future<void> settle() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

GearOrderController make(FakeApi api) => GearOrderController(api,
    userId: 'u1', email: 'jan@example.cz', availDelay: Duration.zero, quoteDelay: Duration.zero);

Map<String, dynamic> ok(String fn, Map<String, dynamic> p) => switch (fn) {
      'get_gear_rental_availability' => {'enabled': false},
      'quote_gear_booking' => {'success': true, 'per_day': 150, 'amount': 300, 'total': 300},
      _ => {'success': true, 'booking_id': 'b-new', 'amount': 300, 'total': 300},
    };

void fillAll(GearOrderController c) {
  c.setBranch('m');
  c.tapDay(DateTime(2026, 11, 20));
  c.tapDay(DateTime(2026, 11, 21));
  c.toggleItem('helmet', true);
  c.pickSize('helmet', 'M');
  c.setContact((x) => x
    ..name = 'Jan Novák'
    ..phone = '+420777111222');
  c.setVop(true);
  c.setGdpr(true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('single branch is preselected; two branches are not', () async {
    final a = make(FakeApi(ok))..configure(data(selfOnly: true));
    expect(a.state.branchId, 'v');
    final b = make(FakeApi(ok))..configure(data());
    expect(b.state.branchId, isNull);
  });

  test('validation order as on the web, then create with consents', () async {
    final api = FakeApi(ok);
    final c = make(api)..configure(data());
    Future<String?> err() async {
      await c.submit('cs');
      return c.state.error?.key;
    }

    expect(await err(), 'groErrBranch');
    c.setBranch('m');
    expect(await err(), 'groErrDates');
    c.tapDay(DateTime(2026, 11, 20));
    expect(await err(), 'groErrItems');
    c.toggleItem('helmet', true);
    expect(await err(), 'groErrSize');
    expect(c.state.error!.args['item'], 'Helma');
    c.pickSize('helmet', 'M');
    expect(await err(), 'groErrContact');
    c.setContact((x) => x
      ..name = 'Jan Novák'
      ..phone = '777111222');
    expect(await err(), 'groErrAgree');
    c.setVop(true);
    c.setGdpr(true);
    expect(api.of('create_web_gear_booking'), isEmpty);
    final created = await c.submit('de');
    expect(created?.bookingId, 'b-new');
    expect(created?.amount, 300);
    final p = api.of('create_web_gear_booking').single;
    expect(p['p_branch_id'], 'm');
    expect(p['p_start'], '2026-11-20');
    expect(p['p_end'], '2026-11-20');
    expect(p['p_items'], [
      {'key': 'helmet', 'size': 'M'}
    ]);
    expect(p['p_customer']['email'], 'jan@example.cz');
    expect(p['p_customer'].containsKey('company'), isFalse);
    expect(p['p_pickup_time'], '09:00');
    expect(p['p_return_time'], isNull);
    expect(p['p_lang'], 'de');
    expect(p['p_note'], isNull);
    expect(p['p_voucher_code'], isNull);
    expect(p['p_existing_booking_id'], isNull);
    expect(p['p_consents'], {'vop': true, 'gdpr': true});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('gear_draft_u1'), 'b-new');
  });

  test('self-service branch: no pickup time; company only when switched on', () async {
    final api = FakeApi(ok);
    final c = make(api)..configure(data());
    fillAll(c);
    c.setBranch('v');
    c.setCompanyOn(true);
    c.setContact((x) => x
      ..company = 'Firma s.r.o.'
      ..ico = '123');
    await c.submit('cs');
    final p = api.of('create_web_gear_booking').single;
    expect(p['p_pickup_time'], isNull);
    expect(p['p_customer']['company'], 'Firma s.r.o.');
    expect(p['p_customer']['ico'], '123');
  });

  test('unpaid draft is reused; unknown error with a draft retries once without it', () async {
    SharedPreferences.setMockInitialValues({'gear_draft_u1': 'old-draft'});
    var n = 0;
    final api = FakeApi((fn, p) {
      if (fn != 'create_web_gear_booking') return ok(fn, p);
      return ++n == 1 ? {'error': 'failed'} : {'success': true, 'booking_id': 'b2', 'amount': 120};
    });
    final c = make(api);
    await settle();
    c.configure(data());
    fillAll(c);
    final created = await c.submit('cs');
    final creates = api.of('create_web_gear_booking');
    expect(creates.length, 2);
    expect(creates.first['p_existing_booking_id'], 'old-draft');
    expect(creates.last['p_existing_booking_id'], isNull);
    expect(created?.bookingId, 'b2');
  });

  test('error codes map to the web texts', () async {
    Future<GearOrderController> run(Map<String, dynamic> e) async {
      final c = make(FakeApi((fn, p) => fn == 'create_web_gear_booking' ? e : ok(fn, p)))..configure(data());
      fillAll(c);
      await c.submit('cs');
      return c;
    }

    expect((await run({'error': 'bad_size', 'key': 'helmet'})).state.error, const GearMsg('groErrSize', {'n': 5, 'item': 'Helma'}));
    expect((await run({'error': 'branch_closed'})).state.error?.key, 'groErrClosed');
    expect((await run({'error': 'too_long', 'max_days': 7})).state.error?.args['n'], 7);
    expect((await run({'error': 'consents_required'})).state.error?.key, 'groErrAgree');
    expect((await run({'error': 'branch_unavailable'})).state.error?.key, 'groErrBranch');
    expect((await run({'error': 'too_many'})).state.error?.key, 'groErrTooMany');
    expect((await run({'error': 'below_minimum'})).state.error?.key, 'groErrMin');
    expect((await run({'error': 'email_mismatch', 'email': 'a@b.cz'})).state.error, const GearMsg('groErrMismatch', {'email': 'a@b.cz'}));
    expect((await run({'error': 'rpc_error'})).state.error?.key, 'groErrGeneric');
    final stock = await run({
      'error': 'out_of_stock',
      'items': [
        {'key': 'helmet', 'size': 'M', 'free': 0}
      ]
    });
    expect(stock.state.error, const GearMsg('groErrStock', {'items': 'Helma M'}));
    final v = await run({'error': 'bad_voucher'});
    expect(v.state.error?.key, 'groVoucherBad');
    expect(v.state.vstate, 'bad');
    expect(v.state.busy, isFalse);
  });

  test('calendar: first tap = 1 day, second tap = end; limits and closures', () async {
    final c = make(FakeApi(ok))..configure(data());
    c.setBranch('m');
    c.tapDay(DateTime(2026, 11, 18)); // minulost — nic
    expect(c.state.start, isNull);
    expect(c.state.hint.key, 'groHintStart');
    c.tapDay(DateTime(2026, 11, 20));
    expect(c.state.open, isTrue);
    expect(c.state.nDays, 1);
    expect(c.state.hint.key, 'groHintEnd');
    c.tapDay(DateTime(2026, 11, 27)); // přes zavřenou pobočku 25.–26.
    expect(c.state.hint.key, 'groErrClosed');
    expect(c.state.open, isTrue);
    c.tapDay(DateTime(2026, 11, 24));
    expect(c.state.end, DateTime(2026, 11, 24));
    expect(c.state.nDays, 5);
    expect(c.state.hint.key, 'groHintDone');
    c.tapDay(DateTime(2026, 11, 28));
    c.tapDay(DateTime(2026, 12, 5)); // 8 dní > max 5
    expect(c.state.hint, const GearMsg('groErrLong', {'n': 5}));
    c.clearDates();
    expect(c.state.start, isNull);
    // změna pobočky na zavřený termín → termín pryč + hláška
    c.setBranch('v');
    c.tapDay(DateTime(2026, 11, 25));
    c.setBranch('m');
    expect(c.state.start, isNull);
    expect(c.state.hint.key, 'groErrClosed');
  });

  test('set button selects exactly its items, keeps sizes, second tap clears', () {
    final c = make(FakeApi(ok))..configure(data());
    c.toggleItem('helmet', true);
    c.pickSize('helmet', 'L');
    c.toggleSet('set');
    expect(c.state.sel, {'helmet': 'L', 'gloves': ''});
    c.toggleSet('set');
    expect(c.state.sel, isEmpty);
  });

  test('stock + live price: sold-out size dropped, server per day wins, voucher states', () async {
    final api = FakeApi((fn, p) => switch (fn) {
          'get_gear_rental_availability' => {
              'enabled': true,
              'sizes': {
                'helmet': {'M': 0, 'L': 3}
              }
            },
          'quote_gear_booking' => p['p_voucher_code'] == 'DAREK'
              ? {'success': true, 'per_day': 100, 'voucher': {'code': 'DAREK', 'amount': 50}, 'amount': 150}
              : p['p_voucher_code'] == 'SLEVA10'
                  ? {'success': false, 'error': 'bad_voucher'}
                  : {'success': true, 'per_day': 100, 'amount': 200},
          _ => ok(fn, p),
        });
    final c = make(api)..configure(data());
    c.toggleItem('helmet', true);
    c.pickSize('helmet', 'M');
    c.setBranch('m');
    c.tapDay(DateTime(2026, 11, 20));
    c.tapDay(DateTime(2026, 11, 21));
    await settle();
    expect(c.state.sel['helmet'], '');
    expect(c.state.drops.single, const GearMsg('groSizeDropped', {'size': 'M', 'item': 'Helma'}));
    c.applyVoucher('darek');
    expect(c.state.vstate, 'need');
    c.pickSize('helmet', 'L');
    await settle();
    expect(api.of('quote_gear_booking').last['p_voucher_code'], 'DAREK');
    expect(c.state.vstate, 'ok');
    var sum = c.state.summary;
    expect(sum.full, 200);
    expect(sum.voucher, 50);
    expect(sum.pay, 150);
    c.applyVoucher('sleva10');
    await settle();
    expect(c.state.vstate, 'bad');
    expect(c.state.vcode, isEmpty);
    sum = c.state.summary;
    expect(sum.voucher, 0);
    expect(sum.pay, 200);
  });

  test('prefill fills only empty contact fields and switches company on', () {
    final c = make(FakeApi(ok))..configure(data());
    c.setContact((x) => x.phone = '111222333');
    c.prefill({'full_name': 'Jana Malá', 'phone': '999', 'city': 'Brno', 'company_name': 'ACME', 'ico': '1'});
    expect(c.state.contact.name, 'Jana Malá');
    expect(c.state.contact.phone, '111222333');
    expect(c.state.contact.city, 'Brno');
    expect(c.state.companyOn, isTrue);
    expect(c.state.contact.email, 'jan@example.cz');
  });

  test('saved profile size is preselected only when offered and free', () {
    final c = make(FakeApi(ok))..configure(data());
    c.setBranch('v');
    c.toggleItem('helmet', true);
    c.preselectSize('helmet', 'XXS');
    expect(c.state.sel['helmet'], '');
    c.preselectSize('helmet', 'M');
    expect(c.state.sel['helmet'], 'M');
    expect(gearDayState(today, today: today, maxAhead: 1, closures: const [], branchId: 'v'), GearDay.free);
  });

  test('form error disappears once its field is valid; server errors stay', () async {
    final api = FakeApi(ok);
    final c = make(api)..configure(data());
    fillAll(c);
    c.setVop(false);
    c.setGdpr(false);
    await c.submit('cs');
    expect(c.state.error?.key, 'groErrAgree');
    c.setVop(true);
    expect(c.state.error?.key, 'groErrAgree'); // GDPR ještě chybí
    c.setGdpr(true);
    expect(c.state.error, isNull);
    // chyba serveru se stejným textem (consents_required) zůstane do dalšího odeslání
    final s = make(FakeApi((fn, p) => fn == 'create_web_gear_booking' ? {'error': 'consents_required'} : ok(fn, p)))
      ..configure(data());
    fillAll(s);
    await s.submit('cs');
    expect(s.state.error?.key, 'groErrAgree');
    s.setNote('x');
    expect(s.state.error?.key, 'groErrAgree');
  });

  test('draft with a payment still in flight is not overwritten (new booking instead)', () async {
    SharedPreferences.setMockInitialValues({'gear_draft_u1': 'old-draft'});
    await PaymentPendingMarker.set('old-draft', clientSecret: 'pi_1_secret_x');
    final api = FakeApi(ok);
    final c = make(api);
    await settle();
    expect(c.state.draftId, 'old-draft');
    c.configure(data());
    fillAll(c);
    final created = await c.submit('cs');
    expect(api.of('create_web_gear_booking').single['p_existing_booking_id'], isNull);
    expect(created?.bookingId, 'b-new');
    expect(created?.reused, isFalse);
  });
}
