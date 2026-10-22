// verify:render cases — booking form "nic nevyplňovat dvakrát" (owner
// 2026-10-22): return address taken from the pickup (answered row with
// "Stejná jako u přistavení" + "Změnit"), own voucher chips in the promo
// card and dialog, the address sheet with its quick options, passenger
// sizes prefilled / reopened with "Odebrat", boots marked "naposledy".
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/booking_form_widget.dart';
import 'package:motogo_app/core/v2/motion/mg_anim.dart';
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/booking/my_vouchers.dart';
import 'package:motogo_app/features/booking/v2/sections/extras_rows_v2.dart';
import 'package:motogo_app/features/booking/v2/sections/handover_v2.dart';
import 'package:motogo_app/features/booking/v2/sections/promo_v2.dart';

import '../support/fakes_booking.dart';
import 'render_harness.dart';

const _gear = {
  ...kProfileOk,
  'gear_sizes': {
    'rider': {'helmet': 'M', 'boots': '43'},
    'passenger': {'helmet': 'L', 'gloves': 'M', 'jacket': 'XL', 'pants': 'L'},
  },
};
const _vouchers = [MyVoucher(code: 'DAR1000', amount: 1000), MyVoucher(code: 'VANOCE2026', amount: 2500)];

Future<void> _tapIn(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f, warnIfMissed: false);
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

Finder _returnAddressRow() =>
    find.descendant(of: find.byType(BookingHandoverV2).at(1), matching: find.byType(MgPress)).last;

List<RenderCase> bookingPrefillRenderCases() {
  RenderCase c(String state, List<Override> Function() o, {Future<void> Function(WidgetTester)? after}) =>
      RenderCase('booking', 'prefill', state, () => const BookingDebugWrapper(), o, after: after);
  List<Override> withVouchers(List<Override> o, [List<MyVoucher> v = const []]) =>
      [...o, myVouchersProvider.overrideWith((ref) async => v)];
  final same = bookingDraft(kBmw, pickupMethod: 'delivery', returnMethod: 'delivery').copyWith(
    returnCity: () => 'Jihlava',
    returnAddress: () => 'Masarykovo náměstí 1',
  );
  final passenger = SelectedExtra(
      id: 'extra-spolujezdec', name: 'Výbava spolujezdce', price: 0, size: 'Helma: L, Rukavice: M, Bunda: XL, Kalhoty: L');
  return [
    c('same_address', () => withVouchers([
          ...bookingOverrides(moto: kBmw, draft: same, pickupFee: 1200, pickupKm: 25),
        ])),
    c('vouchers', () => withVouchers(bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw)), _vouchers)),
    c('voucher_dialog', () => withVouchers(bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw)), _vouchers),
        after: (t) => _tapIn(t, find.descendant(of: find.byType(BookingPromoV2), matching: find.byType(MgPress)).first)),
    c('address_sheet', () => withVouchers(bookingOverrides(
            moto: kBmw, draft: bookingDraft(kBmw, pickupMethod: 'delivery', returnMethod: 'delivery'))),
        after: (t) => _tapIn(t, _returnAddressRow())),
    c('passenger_prefilled', () => withVouchers(bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw), profile: _gear)),
        after: (t) => _tapIn(t, find.byType(BookingExtraRowV2).at(0))),
    c('passenger_edit', () => withVouchers(
            bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw, extras: [passenger]), profile: _gear)),
        after: (t) => _tapIn(t, find.byType(BookingExtraRowV2).at(0))),
    c('boots_last', () => withVouchers(bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw), profile: _gear)),
        after: (t) => _tapIn(t, find.byType(BookingExtraRowV2).at(1))),
  ];
}
