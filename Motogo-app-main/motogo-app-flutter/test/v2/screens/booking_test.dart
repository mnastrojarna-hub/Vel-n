// v2 booking form `/booking` (PLAN §5.3, area "booking"): every state in
// all 8 languages × 360×780 and 412×915 — fails on any exception or
// overflow; PNGs into MG_SHOTS_DIR when set (+ tall full-scroll shots).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/booking_form_widget.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/motion/mg_anim.dart';
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/booking/v2/booking_date_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_booking.dart';
import '../support/v2_harness.dart';

typedef _Case = ({String name, List<Override> Function() overrides, Future<void> Function(WidgetTester)? after});

Future<void> _openCalendar(WidgetTester t) async {
  final change = find.descendant(of: find.byType(BookingDateCardV2), matching: find.byType(MgPress)).first;
  await t.ensureVisible(change);
  await t.pump();
  await t.tap(change, warnIfMissed: false);
  await t.pump(const Duration(milliseconds: 400));
}

List<_Case> _bookingCases() {
  final passenger = SelectedExtra(id: 'extra-spolujezdec', name: 'Výbava spolujezdce', price: 0, size: 'L');
  final bootsNoSize = SelectedExtra(id: 'extra-boty-ridic', name: 'Boty řidiče', price: 0);
  final bootsSized = SelectedExtra(id: 'extra-boty-ridic', name: 'Boty řidiče', price: 0, size: '43');
  final codes = [
    AppliedDiscount(code: 'JARO10', type: DiscountType.percent, value: 10),
    AppliedDiscount(code: 'POUKAZ500', type: DiscountType.fixed, value: 500, calculatedAmount: 500, isVoucher: true),
  ];
  return [
    (name: 'complete', overrides: () => bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw)), after: null),
    (name: 'no_dates', overrides: () => bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw, dates: false)), after: null),
    (
      name: 'calendar_open',
      overrides: () => bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw)),
      after: _openCalendar,
    ),
    (
      name: 'missing_sizes',
      overrides: () => bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw, sizes: false, extras: [bootsNoSize])),
      after: null,
    ),
    (name: 'consents_off', overrides: () => bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw, consents: false)), after: null),
    (name: 'self_service', overrides: () => bookingOverrides(moto: kHusq, draft: bookingDraft(kHusq)), after: null),
    (
      name: 'self_service_late',
      overrides: () => bookingOverrides(moto: kHusq, draft: bookingDraft(kHusq, pickupTime: '12:00')),
      after: null,
    ),
    (name: 'kids', overrides: () => bookingOverrides(moto: kKids, draft: bookingDraft(kKids, kids: true)), after: null),
    (
      name: 'delivery',
      overrides: () => bookingOverrides(
            moto: kBmw,
            draft: bookingDraft(kBmw, pickupMethod: 'delivery', returnMethod: 'delivery'),
            pickupFee: 1200,
            pickupKm: 5,
          ),
      after: null,
    ),
    (
      name: 'extras_promo_note',
      overrides: () => bookingOverrides(
            moto: kBmw,
            draft: bookingDraft(kBmw, extras: [passenger, bootsSized], discounts: codes, notes: 'Přijedu autem, prosím o parkování.'),
          ),
      after: null,
    ),
    (name: 'own_gear', overrides: () => bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw, sizes: false, ownGear: true)), after: null),
    (
      name: 'errors',
      overrides: () => bookingOverrides(
            moto: kBmw,
            draft: bookingDraft(kBmw),
            profile: const {'license_group': ['B'], 'street': '', 'city': 'Pelhřimov', 'zip': ''},
            bookedError: Exception('net'),
          ),
      after: null,
    ),
    (name: 'booked_loading', overrides: () => bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw), bookedLoading: true), after: null),
    (
      name: 'loyalty_fail',
      overrides: () => bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw), loyaltyError: Exception('rpc')),
      after: null,
    ),
    (name: 'rank0_guest', overrides: () => bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw), loyalty: null), after: null),
    (name: 'no_moto', overrides: () => bookingOverrides(moto: null), after: null),
  ];
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerCatalogStrings();
    registerBookingStrings();
    mockBookingPathProvider();
  });
  setUp(() {
    MgMotion.resetSession();
    SharedPreferences.setMockInitialValues({});
  });

  final cases = _bookingCases();

  for (final c in cases) {
    group(c.name, () {
      for (final lang in kV2Langs) {
        for (final size in kV2Sizes) {
          testWidgets('$lang ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
            final key = GlobalKey();
            await pumpV2(tester, const BookingDebugWrapper(), lang: lang, size: size, overrides: c.overrides(), boundaryKey: key);
            await tester.pump();
            if (c.after != null) await c.after!(tester);
            await expectCleanFrames(tester);
            await tester.pump(const Duration(milliseconds: 600));
            expect(tester.takeException(), isNull);
            await maybeShot(tester, key, 'booking__form__${c.name}__${lang}__${size.width.toInt()}x${size.height.toInt()}');
          });
        }
      }
    });
  }

  group('reduced motion settles', () {
    for (final c in cases.where((c) => !c.name.contains('loading'))) {
      testWidgets(c.name, (tester) async {
        await pumpV2(tester, const BookingDebugWrapper(), overrides: c.overrides(), reducedMotion: true);
        await tester.pump();
        await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
        expect(tester.takeException(), isNull);
      });
    }
  });

  // Full-scroll review shots (only with MG_SHOTS_DIR): the whole form in one PNG.
  group('tall shots', () {
    for (final c in cases.where((c) => const {'complete', 'missing_sizes', 'self_service', 'extras_promo_note', 'errors', 'kids', 'delivery'}.contains(c.name))) {
      for (final lang in const ['cs', 'en', 'de']) {
        testWidgets('${c.name} $lang', (tester) async {
          final key = GlobalKey();
          await pumpV2(tester, const BookingDebugWrapper(),
              lang: lang, size: const Size(412, 3800), overrides: c.overrides(), boundaryKey: key);
          await tester.pump();
          await expectCleanFrames(tester);
          await tester.pump(const Duration(milliseconds: 600));
          expect(tester.takeException(), isNull);
          await maybeShot(tester, key, 'booking__tall__${c.name}__${lang}__412x3800');
        });
      }
    }
  });
}
