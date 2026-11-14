// Hlídač výpůjčky: výpůjčka JEN výbavy (`booking_kind = 'gear'`) se nikdy
// nenahrává jako jízda (GEAR_RENTAL_APP.md §5) — ani když ji RLS po zapnutí
// „Zobrazit v aplikaci" začne appce posílat.
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/features/reservations/reservation_models.dart';
import 'package:motogo_app/features/routes/ride_recorder_watcher.dart';

Reservation res(String id, {String? kind, String? moto = 'm1'}) {
  final now = DateTime.now();
  String d(DateTime x) => '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
  return Reservation.fromJson({
    'id': id,
    'moto_id': moto,
    'status': 'active',
    'payment_status': 'paid',
    'start_date': d(now.subtract(const Duration(days: 1))),
    'end_date': d(now.add(const Duration(days: 1))),
    'pickup_time': '08:00',
    'created_at': now.subtract(const Duration(days: 3)).toIso8601String(),
    if (kind != null) 'booking_kind': kind,
  });
}

void main() {
  test('převzatá výpůjčka motorky se nahrává, výbava ne', () {
    expect(rideActiveBookingId([res('b1')]), 'b1');
    expect(rideActiveBookingId([res('b1', kind: 'moto')]), 'b1');
    expect(rideActiveBookingId([res('g1', kind: 'gear', moto: null)]), isNull);
    expect(rideActiveBookingId([res('g1', kind: 'gear', moto: null), res('b2')]), 'b2');
    expect(res('g1', kind: 'gear').isGearOnly, isTrue);
    expect(res('b1').isGearOnly, isFalse);
  });
}
