// Calculator with delivery (owner 2026-11-27) — pure logic: `quoteFor`
// with the fees of step ④ is the booking form's own price for the same
// input (loyalty never touches delivery, the 12:00 saving is unchanged),
// the calculator's handover state follows the form's rules (current-state
// writes, another branch / account dropped, blocked → back to the branch)
// and the two new texts exist in 8 languages.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/booking_address_carry.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/i18n/translations_ext_68_calc_delivery.dart';
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/booking/booking_provider.dart';
import 'package:motogo_app/features/booking/booking_quote.dart';
import 'package:motogo_app/features/booking/price_calculator.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_state.dart';
import 'package:motogo_app/features/loyalty/loyalty_provider.dart';

import '../support/fakes_booking.dart';
import '../support/fakes_calc_delivery.dart';
import '../support/v2_harness.dart' show kV2Langs;

LoyaltyStatus? _rank(int pct) => pct == 0
    ? null
    : LoyaltyStatus(level: pct, percent: pct, rankName: 'Rank $pct', colorHex: '#37CF63', qualifyingCount: 5);

void main() {
  final (ws, we) = futureWeekend();

  group('quoteFor with delivery fees = the booking form price', () {
    for (final pct in [0, 3, 20]) {
      for (final sides in [(true, false), (false, true), (true, true)]) {
        test('rank $pct %, pickup ${sides.$1}, return ${sides.$2}', () async {
          final h = jihlavaHandover(pickup: sides.$1, ret: sides.$2);
          final loyalty = _rank(pct);
          final q = quoteFor(kBmw, ws, we, loyalty: loyalty, pickupDeliveryFee: h.pickupDue, returnDeliveryFee: h.returnDue);
          // The form: the same bike, dates and handover in ITS providers.
          final c = ProviderContainer(overrides: [
            bookingMotoProvider.overrideWith((_) => kBmw),
            bookingDraftProvider.overrideWith((_) => h.applyTo(BookingDraft(motoId: kBmw.id, startDate: ws, endDate: we))),
            pickupDelivFeeProvider.overrideWith((_) => h.pickupFee),
            returnDelivFeeProvider.overrideWith((_) => h.returnFee),
            loyaltyStatusProvider.overrideWith((_) async => loyalty),
          ]);
          addTearDown(c.dispose);
          await c.read(loyaltyStatusProvider.future);
          final bd = c.read(priceBreakdownProvider);
          expect(q.total, bd.total);
          expect([q.basePrice, q.pickupDeliveryFee, q.returnDeliveryFee, q.loyaltyDiscount],
              [bd.basePrice, bd.pickupDeliveryFee, bd.returnDeliveryFee, bd.loyaltyDiscount]);
          // Loyalty is counted from the rental only — never from delivery.
          final plain = quoteFor(kBmw, ws, we, loyalty: loyalty);
          expect(q.loyaltyDiscount, plain.loyaltyDiscount);
          expect(q.total, plain.total + h.pickupDue + h.returnDue);
          // The 12:00 saving does not depend on delivery.
          final q12 = quoteFor(kBmw, ws, we,
              pickupTime: '12:00', loyalty: loyalty, pickupDeliveryFee: h.pickupDue, returnDeliveryFee: h.returnDue);
          final plain12 = quoteFor(kBmw, ws, we, pickupTime: '12:00', loyalty: loyalty);
          expect(q.total - q12.total, plain.total - plain12.total);
        });
      }
    }

    test('default arguments = the quote before 2026-11-27 (no delivery)', () {
      final q = quoteFor(kBmw, ws, we, loyalty: kLoyalty3);
      final old = PriceCalculator.calculate(
        prices: kBmw.prices,
        startDate: ws,
        endDate: we,
        extras: const [],
        pickupDeliveryFee: 0,
        returnDeliveryFee: 0,
        discounts: const [],
        loyaltyPercent: kLoyalty3.percent,
        loyaltyLevel: kLoyalty3.level,
        loyaltyRankName: kLoyalty3.rankName,
      );
      expect([q.total, q.pickupDeliveryFee, q.returnDeliveryFee], [old.total, 0, 0]);
      expect(listQuoteFor(kBmw, ws, we).total, quoteFor(kBmw, ws, we).total);
    });
  });

  group('HandoverChoice', () {
    test('a fee counts only on a side set to delivery (as priceBreakdownProvider)', () {
      final h = jihlavaHandover(pickup: true, ret: true);
      expect([h.pickupDue, h.returnDue], [kRouteFee, kRouteFee]);
      final back = h.copyWith(draft: h.draft.copyWith(pickupMethod: 'store'));
      expect([back.pickupDue, back.returnDue, back.pickupFee], [0, kRouteFee, kRouteFee]);
      expect(HandoverChoice().pickupDue + HandoverChoice().returnDue, 0);
    });

    test('delivery without an address: no fee yet, flagged as missing', () {
      final h = HandoverChoice(draft: BookingDraft(pickupMethod: 'delivery'));
      expect([h.pickupNoAddress, h.returnNoAddress, h.pickupDue], [true, false, 0]);
      expect(jihlavaHandover().pickupNoAddress, isFalse);
    });

    test('applyTo writes the place only; equality = place + price', () {
      final base = BookingDraft(motoId: 'm', pickupTime: '12:00', notes: 'x', helmetSize: 'L', pickupMethod: 'delivery', pickupCity: 'Brno');
      final d = jihlavaHandover(pickup: false, ret: true).applyTo(base);
      expect([d.motoId, d.pickupTime, d.notes, d.helmetSize], ['m', '12:00', 'x', 'L']);
      expect([d.pickupMethod, d.pickupCity, d.returnMethod, d.returnCity, d.returnAddress],
          ['store', null, 'delivery', 'Jihlava', 'Masarykovo náměstí 1']);
      expect(jihlavaHandover(), jihlavaHandover());
      expect(jihlavaHandover() == jihlavaHandover().copyWith(pickupFee: 1), isFalse);
      expect(HandoverChoice.of(base).draft.notes, isNull, reason: 'only pickup*/return* fields');
      expect(HandoverChoice.of(base), HandoverChoice(draft: BookingDraft(pickupMethod: 'delivery', pickupCity: 'Brno')));
    });
  });

  group('CalcStateNotifier handover', () {
    late ProviderContainer box;
    late CalcStateNotifier n;
    CalcState st() => box.read(calcStateProvider);
    setUp(() {
      box = ProviderContainer();
      addTearDown(box.dispose);
      n = box.read(calcStateProvider.notifier);
    });

    test('writes start from the CURRENT choice (price, then address; the other side takes both)', () {
      final seed = HandoverChoice();
      void change(HandoverChoice Function(HandoverChoice) fn) => n.updateHandover(fn, seed: seed, branchId: 'b-mezna');
      change((c) => c.copyWith(draft: c.draft.copyWith(pickupMethod: 'delivery')));
      // The address sheet: onDistCalc, then onSave.
      change((c) => c.copyWith(pickupFee: kRouteFee, pickupKm: kRouteKm));
      change((c) => c.copyWith(draft: c.draft.copyWith(pickupCity: () => 'Jihlava', pickupAddress: () => 'Fritzova 3')));
      var h = st().handover!.choice;
      expect([h.draft.pickupMethod, h.draft.pickupCity, h.pickupFee, h.pickupKm, h.pickupDue],
          ['delivery', 'Jihlava', kRouteFee, kRouteKm, kRouteFee]);
      expect(st().handover!.branchId, 'b-mezna');
      // The shared helper, with the calculator's own fee store.
      final fees = HandoverFees(
        pickupFee: () => st().handover!.choice.pickupFee,
        pickupKm: () => st().handover!.choice.pickupKm,
        returnFee: () => st().handover!.choice.returnFee,
        returnKm: () => st().handover!.choice.returnKm,
        setPickup: (f, k) => change((c) => c.copyWith(pickupFee: f, pickupKm: k)),
        setReturn: (f, k) => change((c) => c.copyWith(returnFee: f, returnKm: k)),
      );
      expect([fees.returnFee(), fees.pickupKm()], [0, kRouteKm]);
      fees.setReturn(fees.pickupFee(), fees.pickupKm());
      h = st().handover!.choice;
      expect([h.returnFee, h.returnKm, h.returnDue], [kRouteFee, kRouteKm, 0], reason: 'return still at the branch');
    });

    test('a seed is used only until something valid for the bike was chosen', () {
      final seed = jihlavaHandover(ret: true);
      n.updateHandover((c) => c.copyWith(draft: c.draft.copyWith(pickupMethod: 'store')), seed: seed, branchId: 'b-mezna');
      expect(st().handover!.choice.returnDue, kRouteFee, reason: 'the untouched side keeps what the step showed');
      n.updateHandover((c) => c, seed: HandoverChoice(), branchId: 'b-mezna');
      expect(st().handover!.choice.returnDue, kRouteFee);
      // Another branch / another account: the old choice is not the base.
      n.updateHandover((c) => c, seed: HandoverChoice(), branchId: 'b-vn');
      expect(st().handover!.choice.returnDue, 0);
      n.updateHandover((c) => c, seed: seed, branchId: 'b-vn', owner: 'user-b');
      expect([st().handover!.owner, st().handover!.choice.returnDue], ['user-b', kRouteFee]);
    });

    test('normalize: another branch or account → dropped; blocked → both sides at the branch', () {
      void seedIt() => n.updateHandover((c) => c, seed: jihlavaHandover(ret: true), branchId: 'b-mezna', owner: 'u1');
      seedIt();
      n.normalizeHandover(branchId: 'b-mezna', owner: 'u1', blocked: false);
      expect(st().handover!.choice.pickupDue, kRouteFee, reason: 'valid → untouched');
      n.normalizeHandover(branchId: 'b-vn', owner: 'u1', blocked: true);
      expect(st().handover, isNull);
      seedIt();
      n.normalizeHandover(branchId: 'b-mezna', owner: 'u2', blocked: false);
      expect(st().handover, isNull);
      seedIt();
      n.normalizeHandover(branchId: 'b-mezna', owner: 'u1', blocked: true);
      final h = st().handover!.choice;
      expect([h.draft.pickupMethod, h.draft.returnMethod, h.pickupDue, h.returnDue, h.draft.pickupCity],
          ['store', 'store', 0, 0, 'Jihlava'], reason: 'the form keeps the address, only the method goes back');
    });

    test('lifecycle: dates / bike / branch keep it, a paid booking and the hand-over clear it', () {
      void seedIt() => n.updateHandover((c) => c, seed: jihlavaHandover(), branchId: 'b-mezna');
      seedIt();
      n
        ..setRange(ws, we)
        ..setMoto(kBmw.id)
        ..setBranch('b-mezna', currentMoto: kBmw)
        ..clearDates()
        ..setStart(ws)
        ..prefill(motoId: kBmw.id, start: ws, end: we);
      expect(st().handover!.choice.pickupDue, kRouteFee);
      n.clearHandover();
      expect(st().handover, isNull);
      seedIt();
      n.resetTrip();
      expect([st().handover, st().motoId], [null, null]);
    });
  });

  test('the new texts: 8 languages, non-empty, registered', () {
    final keys = translationsExt68CalcDelivery['cs']!.keys.toList();
    expect(keys, ['cdHandoverInfo', 'cdHandoverNoMoto']);
    for (final l in kV2Langs) {
      expect(translationsExt68CalcDelivery[l]!.keys.toList(), keys, reason: l);
      for (final k in keys) {
        expect(translations[l]![k]!.trim(), isNotEmpty, reason: '$l $k');
        expect(translations[l]![k], translationsExt68CalcDelivery[l]![k]);
      }
    }
    // Texts reused from the booking form exist everywhere too.
    for (final k in [
      'v2BkPickupTitle', 'v2BkReturnTitle', 'atBranch', 'v2BkDeliveryTo', 'v2BkReturnFrom', 'deliveryPriceInfo',
      'deliveryFrom', 'ssNoDeliveryShort', 'ssNoDeliveryInfo', 'deliveryFee', 'returnFee', 'efoNoAddrCtx',
      'efoNoRetAddrCtx', 'validationDeliveryLeadTime', 'v2BkEnterAddress',
    ]) {
      for (final l in kV2Langs) {
        expect(translations[l]![k]?.trim() ?? '', isNotEmpty, reason: '$l $k');
      }
    }
  });
}
