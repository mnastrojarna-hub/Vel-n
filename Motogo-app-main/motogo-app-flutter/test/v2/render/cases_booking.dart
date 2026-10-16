// verify:render cases — booking form v2 `/booking` (ported from
// booking_test.dart): complete / no dates / calendar open / missing sizes /
// consents off / self-service (+ 12:00) / kids / delivery / extras + promo
// + note / own gear / errors / availability loading / loyalty failure /
// guest / no bike.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/booking_form_widget.dart';
import 'package:motogo_app/core/v2/motion/mg_anim.dart';
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/booking/v2/booking_date_v2.dart';

import '../support/fakes_booking.dart';
import 'render_harness.dart';

Future<void> _openCalendar(WidgetTester t) async {
  final change = find.descendant(of: find.byType(BookingDateCardV2), matching: find.byType(MgPress)).first;
  await t.ensureVisible(change);
  await t.pump();
  await t.tap(change, warnIfMissed: false);
  await t.pump(const Duration(milliseconds: 400));
}

List<RenderCase> bookingRenderCases() {
  final passenger = SelectedExtra(id: 'extra-spolujezdec', name: 'Výbava spolujezdce', price: 0, size: 'L');
  final bootsNoSize = SelectedExtra(id: 'extra-boty-ridic', name: 'Boty řidiče', price: 0);
  final bootsSized = SelectedExtra(id: 'extra-boty-ridic', name: 'Boty řidiče', price: 0, size: '43');
  final codes = [
    AppliedDiscount(code: 'JARO10', type: DiscountType.percent, value: 10),
    AppliedDiscount(code: 'POUKAZ500', type: DiscountType.fixed, value: 500, calculatedAmount: 500, isVoucher: true),
  ];
  RenderCase c(String state, List<Override> Function() o, {Future<void> Function(WidgetTester)? after, bool loading = false}) =>
      RenderCase('booking', 'form', state, () => const BookingDebugWrapper(), o, after: after, loading: loading);
  return [
    c('complete', () => bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw))),
    c('no_dates', () => bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw, dates: false))),
    c('calendar_open', () => bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw)), after: _openCalendar),
    c('missing_sizes', () => bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw, sizes: false, extras: [bootsNoSize]))),
    c('consents_off', () => bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw, consents: false))),
    c('self_service', () => bookingOverrides(moto: kHusq, draft: bookingDraft(kHusq))),
    c('self_service_late', () => bookingOverrides(moto: kHusq, draft: bookingDraft(kHusq, pickupTime: '12:00'))),
    c('kids', () => bookingOverrides(moto: kKids, draft: bookingDraft(kKids, kids: true))),
    c('delivery', () => bookingOverrides(
        moto: kBmw, draft: bookingDraft(kBmw, pickupMethod: 'delivery', returnMethod: 'delivery'), pickupFee: 1200, pickupKm: 5)),
    c('extras_promo_note', () => bookingOverrides(
        moto: kBmw,
        draft: bookingDraft(kBmw, extras: [passenger, bootsSized], discounts: codes, notes: 'Přijedu autem, prosím o parkování.'))),
    c('own_gear', () => bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw, sizes: false, ownGear: true))),
    c('errors', () => bookingOverrides(
        moto: kBmw,
        draft: bookingDraft(kBmw),
        profile: const {'license_group': ['B'], 'street': '', 'city': 'Pelhřimov', 'zip': ''},
        bookedError: Exception('net'))),
    c('booked_loading', () => bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw), bookedLoading: true), loading: true),
    c('loyalty_fail', () => bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw), loyaltyError: Exception('rpc'))),
    c('rank0_guest', () => bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw), loyalty: null)),
    c('no_moto', () => bookingOverrides(moto: null)),
  ];
}
