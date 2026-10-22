// Owner 2026-10-22 "nikdy nic vyplňovat dvakrát" — pure logic: the v2
// booking entry keeps the unfinished draft (same bike: everything, only the
// dates move; another bike: what does not depend on the bike), the handover
// address is carried to the other side with its price, the address sheet
// offers the other side + the profile address, own vouchers are listed
// without the applied ones; the new ext_46 strings exist in 8 languages.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/booking_address_carry.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/i18n/translations_ext_46_booking_prefill.dart';
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/booking/booking_provider.dart';
import 'package:motogo_app/features/booking/my_vouchers.dart';
import 'package:motogo_app/features/booking/v2/booking_carry_v2.dart';

import '../support/fakes_booking.dart';
import '../support/fakes_catalog.dart' show kShotgun;
import '../support/v2_harness.dart' show kV2Langs;

void main() {
  final (s, e) = futureWeekend();
  final s2 = DateTime(s.year, s.month, s.day + 7), e2 = DateTime(e.year, e.month, e.day + 7);
  final code = AppliedDiscount(code: 'POUKAZ500', type: DiscountType.fixed, value: 500, isVoucher: true);
  final passenger = SelectedExtra(id: 'extra-spolujezdec', name: 'Výbava spolujezdce', price: 0, size: 'Helma: L');
  final boots = SelectedExtra(id: 'extra-boty-ridic', name: 'Boty řidiče', price: 0, size: '43');
  final trailer = SelectedExtra(id: 'extra-vozik', name: 'Vozík', price: 0);

  BookingDraft filled() => BookingDraft(
        motoId: kBmw.id,
        motoName: kBmw.model,
        startDate: s,
        endDate: e,
        pickupTime: '12:00',
        returnTime: '18:00',
        pickupMethod: 'delivery',
        returnMethod: 'delivery',
        pickupCity: 'Jihlava',
        pickupAddress: 'Masarykovo náměstí 1',
        returnCity: 'Jihlava',
        returnAddress: 'Masarykovo náměstí 1',
        extras: [passenger, boots, trailer],
        trailerMotoId: 'tr-1',
        discounts: [code],
        notes: 'Přijedu vlakem',
        helmetSize: 'M',
        glovesSize: 'L',
        jacketSize: 'L',
        pantsSize: 'M',
        consentVop: true,
        consentGdpr: true,
        consentKids: true,
      );
  BookingDraft fresh(String id, DateTime a, DateTime b) =>
      BookingDraft(motoId: id, motoName: id, startDate: a, endDate: b, helmetSize: 'XL', glovesSize: 'XL');

  group('carryBookingDraft (v2 entry)', () {
    test('no draft / submitted draft → the fresh draft (old behaviour)', () {
      final f = fresh(kBmw.id, s, e);
      expect(identical(carryBookingDraft(prev: BookingDraft(), prevMoto: null, moto: kBmw, fresh: f), f), isTrue);
      expect(identical(carryBookingDraft(prev: filled(), prevMoto: kBmw, moto: kBmw, fresh: f, submitted: true), f), isTrue);
    });

    test('same bike, same dates → the whole draft is kept', () {
      final d = carryBookingDraft(prev: filled(), prevMoto: kBmw, moto: kBmw, fresh: fresh(kBmw.id, s, e));
      expect([d.pickupTime, d.returnTime, d.notes, d.pickupCity, d.returnAddress, d.trailerMotoId],
          ['12:00', '18:00', 'Přijedu vlakem', 'Jihlava', 'Masarykovo náměstí 1', 'tr-1']);
      expect(d.extras.map((x) => x.id), ['extra-spolujezdec', 'extra-boty-ridic', 'extra-vozik']);
      expect([d.helmetSize, d.consentVop, d.consentGdpr, d.discounts.single.code], ['M', true, true, 'POUKAZ500']);
    });

    test('same bike, new dates → only the dates move; the trailer piece is released', () {
      final d = carryBookingDraft(prev: filled(), prevMoto: kBmw, moto: kBmw, fresh: fresh(kBmw.id, s2, e2));
      expect([d.startDate, d.endDate], [s2, e2]);
      expect(d.trailerMotoId, isNull);
      expect(d.extras.map((x) => x.id), ['extra-spolujezdec', 'extra-boty-ridic']);
      expect([d.pickupTime, d.notes, d.pickupMethod, d.helmetSize], ['12:00', 'Přijedu vlakem', 'delivery', 'M']);
    });

    test('another bike at the same branch → bike-independent fields + delivery + extras', () {
      final d = carryBookingDraft(prev: filled(), prevMoto: kBmw, moto: kShotgun, fresh: fresh(kShotgun.id, s, e));
      expect([d.motoId, d.startDate, d.pickupTime, d.returnTime, d.notes], [kShotgun.id, s, '12:00', '18:00', 'Přijedu vlakem']);
      expect([d.helmetSize, d.glovesSize, d.jacketSize, d.pantsSize], ['M', 'L', 'L', 'M']);
      expect([d.pickupMethod, d.returnMethod, d.pickupCity, d.returnCity], ['delivery', 'delivery', 'Jihlava', 'Jihlava']);
      expect(d.extras.map((x) => x.id), ['extra-spolujezdec', 'extra-boty-ridic']);
      expect([d.trailerMotoId, d.consentVop, d.consentGdpr, d.consentKids], [null, true, true, false]);
      expect(d.discounts.single.code, 'POUKAZ500');
      expect(carryDropsDelivery(filled(), kBmw, kShotgun), isFalse);
    });

    test('another branch → handover back to the branch, no extras, sizes + time kept', () {
      final d = carryBookingDraft(prev: filled(), prevMoto: kBmw, moto: kHusq, fresh: fresh(kHusq.id, s, e));
      expect([d.pickupMethod, d.returnMethod, d.pickupCity, d.returnAddress], ['store', 'store', null, null]);
      expect(d.extras, isEmpty);
      expect([d.pickupTime, d.helmetSize, d.notes], ['12:00', 'M', 'Přijedu vlakem']);
      expect(carryDropsDelivery(filled(), kBmw, kHusq), isTrue);
    });

    test('own gear stays own gear (no sizes); missing sizes fall back to the profile', () {
      final own = filled().copyWith(ownGear: true, helmetSize: () => null);
      final d = carryBookingDraft(prev: own, prevMoto: kBmw, moto: kHusq, fresh: fresh(kHusq.id, s, e));
      expect([d.ownGear, d.helmetSize, d.glovesSize], [true, null, null]);
      final gap = filled().copyWith(helmetSize: () => null);
      expect(carryBookingDraft(prev: gap, prevMoto: kBmw, moto: kHusq, fresh: fresh(kHusq.id, s, e)).helmetSize, 'XL');
    });

    test('detail dates follow a form change of the same bike only', () {
      final a = filled();
      final b = a.copyWith(startDate: () => s2, endDate: () => e2);
      expect(followDraftDates(a, b, kBmw.id), (s2, e2));
      expect(followDraftDates(a, b, kHusq.id), isNull);
      expect(followDraftDates(b, b.copyWith(notes: () => 'x'), kBmw.id), isNull);
    });
  });

  group('handover address carry', () {
    late WidgetRef ref;
    late ProviderContainer c;
    Future<void> pump(WidgetTester t, BookingDraft d, {double fee = 0, double km = 0}) async {
      c = ProviderContainer(overrides: [
        bookingDraftProvider.overrideWith((_) => d),
        pickupDelivFeeProvider.overrideWith((_) => fee),
        pickupDistKmProvider.overrideWith((_) => km),
      ]);
      addTearDown(c.dispose);
      await t.pumpWidget(UncontrolledProviderScope(
          container: c,
          child: Consumer(builder: (_, r, __) {
            ref = r;
            return const SizedBox();
          })));
    }

    void upd(BookingDraft Function(BookingDraft) fn) =>
        c.read(bookingDraftProvider.notifier).state = fn(c.read(bookingDraftProvider));

    final pickupOnly = BookingDraft(pickupMethod: 'delivery', pickupCity: 'Jihlava', pickupAddress: 'Masarykovo náměstí 1');

    testWidgets('return switched to delivery takes the pickup address + its price', (t) async {
      await pump(t, pickupOnly, fee: 1200, km: 25);
      handoverToDelivery(ref, upd, c.read(bookingDraftProvider), pickup: false);
      final d = c.read(bookingDraftProvider);
      expect([d.returnMethod, d.returnCity, d.returnAddress], ['delivery', 'Jihlava', 'Masarykovo náměstí 1']);
      expect([c.read(returnDelivFeeProvider), c.read(returnDistKmProvider)], [1200, 25]);
      expect(handoverSameAddress(d), isTrue);
    });

    testWidgets('a return address of its own is never overwritten', (t) async {
      await pump(t, pickupOnly.copyWith(returnCity: () => 'Brno', returnAddress: () => 'Husova 5'));
      handoverToDelivery(ref, upd, c.read(bookingDraftProvider), pickup: false);
      expect(c.read(bookingDraftProvider).returnCity, 'Brno');
    });

    testWidgets('pickup address change: a linked return follows, a different one stays', (t) async {
      final same = pickupOnly.copyWith(returnMethod: 'delivery', returnCity: () => 'Jihlava', returnAddress: () => 'Masarykovo náměstí 1');
      await pump(t, same, fee: 900);
      handoverSaveAddress(ref, upd, c.read(bookingDraftProvider), pickup: true, city: 'Třebíč', addr: 'Karlovo nám. 2');
      var d = c.read(bookingDraftProvider);
      expect([d.pickupCity, d.returnCity, d.returnAddress], ['Třebíč', 'Třebíč', 'Karlovo nám. 2']);
      expect(c.read(returnDelivFeeProvider), 900);
      upd((x) => x.copyWith(returnCity: () => 'Brno', returnAddress: () => 'Husova 5'));
      handoverSaveAddress(ref, upd, c.read(bookingDraftProvider), pickup: true, city: 'Jihlava', addr: 'Fritzova 3');
      d = c.read(bookingDraftProvider);
      expect([d.pickupCity, d.returnCity], ['Jihlava', 'Brno']);
    });
  });

  test('address sheet quick options: other side + profile, no duplicates', () {
    String tr(String k) => k;
    const profile = {'street': 'Mezná 9', 'city': 'Pelhřimov', 'zip': '39301'};
    final pickupOnly = BookingDraft(pickupMethod: 'delivery', pickupCity: 'Jihlava', pickupAddress: 'Masarykovo náměstí 1');
    var q = handoverQuickOptions(tr, pickupOnly.copyWith(returnMethod: 'delivery'), pickup: false, profile: profile);
    expect(q.map((o) => o.label), ['bkAddrSamePickup', 'bkAddrMine']);
    expect(q.last.line, 'Mezná 9, 39301 Pelhřimov');
    expect(q.last.asSuggestion['_city'], 'Pelhřimov');
    // Pickup at the profile address → one option only; the side's own address is not offered.
    final home = BookingDraft(pickupMethod: 'delivery', pickupCity: 'Pelhřimov', pickupAddress: 'Mezná 9', returnMethod: 'delivery');
    q = handoverQuickOptions(tr, home, pickup: false, profile: profile);
    expect(q.map((o) => o.label), ['bkAddrSamePickup']);
    expect(handoverQuickOptions(tr, home, pickup: true, profile: profile), isEmpty);
  });

  test('own vouchers: applied codes are not offered again', () {
    const all = [MyVoucher(code: 'DAR1000', amount: 1000), MyVoucher(code: 'DAR500', amount: 500)];
    expect(unusedVouchers(all, ['dar1000']).map((v) => v.code), ['DAR500']);
    expect(unusedVouchers(null, const []), isEmpty);
  });

  test('ext_46 strings: 8 languages, same keys, placeholders kept, registered', () {
    final cs = translationsExt46BookingPrefill['cs']!;
    for (final l in kV2Langs) {
      final m = translationsExt46BookingPrefill[l]!;
      expect(m.keys.toSet(), cs.keys.toSet(), reason: l);
      expect(m.values.every((v) => v.trim().isNotEmpty), isTrue, reason: l);
      expect(m['bkVoucherUseA11y'], allOf(contains('{code}'), contains('{amount}')), reason: l);
      expect(translations[l]!['bkAddrMine'], m['bkAddrMine'], reason: l);
      expect(translations[l]!['removeBtn'], isNotNull, reason: l);
    }
  });
}
