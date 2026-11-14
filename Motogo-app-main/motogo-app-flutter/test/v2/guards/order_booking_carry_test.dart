// Safeguards G-159 / G-228 / G-229 / G-230 / G-231 / G-165 / G-207 (new
// look): coming back to the SAME bike keeps the filled-in draft, but — as
// the old look, which always started a fresh draft — the VOP, GDPR and
// guardian consents have to be ticked again (so "Pokračovat k platbě" is
// locked until they are) and a picked trailer is released (it is not
// re-checked and someone else may have booked it meanwhile).
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/booking/v2/booking_carry_v2.dart';

import '../support/fakes_booking.dart';

void main() {
  final (s, e) = futureWeekend();
  final s2 = DateTime(s.year, s.month, s.day + 7), e2 = DateTime(e.year, e.month, e.day + 7);
  BookingDraft prev(DateTime a, DateTime b) => BookingDraft(
        motoId: kBmw.id,
        startDate: a,
        endDate: b,
        notes: 'Přijedu vlakem',
        extras: [
          SelectedExtra(id: 'extra-boty-ridic', name: 'Boty řidiče', price: 0, size: '43'),
          SelectedExtra(id: 'extra-vozik', name: 'Vozík', price: 0),
        ],
        trailerMotoId: 'tr-1',
        consentVop: true,
        consentGdpr: true,
        consentKids: true,
      );
  BookingDraft fresh(DateTime a, DateTime b) => BookingDraft(motoId: kBmw.id, startDate: a, endDate: b);

  for (final (label, a, b) in [('same dates', s, e), ('new dates', s2, e2)]) {
    test('same bike, $label: consents unticked again, trailer released, the rest kept', () {
      final d = carryBookingDraft(prev: prev(s, e), prevMoto: kBmw, moto: kBmw, fresh: fresh(a, b));
      expect([d.consentVop, d.consentGdpr, d.consentKids], [false, false, false], reason: 'G-159/G-228-231');
      expect(d.trailerMotoId, isNull, reason: 'G-207');
      expect(d.extras.map((x) => x.id), ['extra-boty-ridic']);
      expect([d.notes, d.startDate, d.endDate], ['Přijedu vlakem', a, b]);
    });
  }
}
