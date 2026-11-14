// Side effects of the last fixes (review RL-02..RL-04, 2026-11-13), new
// look only, display and guidance:
// RL-02 the "no pickup time left today" line never shows for delivery (a
// branch pickup may still be possible today) — delivery keeps the earlier
// "Změň čas vyzvednutí" guidance; a branch pickup with no slot left keeps
// the new line. RL-03 the swap "pick a free bike first" hint only when a
// free, not blocked bike is on the screen and availability is not loading.
// RL-04 the full-width detail line is an explicit opt-in; every other row
// keeps label + value, also with an empty value.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/states/mg_state_banner.dart';
import 'package:motogo_app/core/v2/widgets/mg_buttons.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/booking/v2/booking_dock_v2.dart';
import 'package:motogo_app/features/booking/v2/booking_form_view_v2.dart';
import 'package:motogo_app/features/booking/v2/booking_sync_v2.dart' show BookingErrKind;
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/reservations/v2/res_detail_bits_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_swap_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_booking.dart';
import '../support/fakes_reservations.dart';
import '../support/v2_harness.dart';

String _cs(String k) => translations['cs']![k]!;
final _shot = GlobalKey();

const _bd = PriceBreakdown(
    basePrice: 12261, extrasTotal: 0, pickupDeliveryFee: 0, returnDeliveryFee: 0, discountTotal: 368, total: 11893, days: 3);

Future<void> _form(WidgetTester t, BookingDraft draft, String err) async {
  await pumpV2(
    t,
    BookingFormV2View(
      moto: kBmw,
      draft: draft,
      bd: _bd,
      pricedExtras: const [],
      err: err,
      profileErr: null,
      hasDates: true,
      dayCount: 3,
      isKids: false,
      selfService: false,
      selfServiceAtBranch: false,
      hideReturnTime: false,
      deliveryBlocked: false,
      branchLabel: 'Mezná',
      missingSizes: const [],
      canProceed: false,
      booked: const AsyncValue.data(<BookedDateRange>[]),
      errKind: BookingErrKind.time,
      calOpen: false,
      onCloseCalendar: () {},
      noteOpen: false,
      noteCtrl: TextEditingController(),
      onUpd: (_) {},
      onBack: () {},
      onOpenCalendar: () {},
      onDatesSelected: (_, __) {},
      onDatesReset: () {},
      onRetryBooked: () {},
      onPickupTime: (_) {},
      onReturnTime: (_) {},
      onToggleNote: () {},
      onNoteChanged: (_) {},
      onVop: (_) {},
      onGdpr: (_) {},
      onKids: (_) {},
      onProceed: () {},
      onCompleteProfile: () {},
    ),
    size: const Size(360, 780),
    overrides: bookingOverrides(moto: kBmw, draft: draft),
    boundaryKey: _shot,
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

Future<void> _done(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 2));
}

BookingDraft _onDay(DateTime d, String method) => bookingDraft(kBmw, pickupMethod: method, pickupTime: '20:00')
    .copyWith(startDate: () => DateTime(d.year, d.month, d.day), endDate: () => DateTime(d.year, d.month, d.day + 2));

Motorcycle _moto(String id, String model) => Motorcycle.fromJson({
      'id': id,
      'model': model,
      'brand': model.split(' ').first,
      'category': 'cestovni',
      'status': 'active',
      'branches': {'name': 'Mezná', 'type': 'obslužná'},
      'license_required': 'A',
      'images': ['https://example.com/$id-1.jpg'],
    });

Widget _swap(Map<String, bool> avail, {bool loading = false, bool Function(Motorcycle)? blocked}) =>
    SingleChildScrollView(
      child: SwapMotoViewV2(
        rangeText: 'Termín rezervace: 1.12.2026 – 5.12.2026',
        dateText: '2.12.2026',
        onPickDate: () {},
        timePicker: const SizedBox(height: 10),
        currentMotoName: 'Husqvarna 701 SM',
        branchFilter: const SizedBox.shrink(),
        motos: AsyncValue.data([_moto('m1', 'BMW R 1250 GS'), _moto('m2', 'Honda Africa Twin')]),
        candidates: (l) => l,
        avail: avail,
        availLoading: loading,
        selectedId: null,
        trailerBlocked: blocked ?? (_) => false,
        onTapMoto: (_, __) {},
        net: null,
        netLoading: false,
        saving: false,
        canConfirm: false,
        onConfirm: () {},
      ),
    );

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerBookingStrings();
    registerReservationStrings();
    mockBookingPathProvider();
  });
  setUp(() {
    MgMotion.resetSession();
    SharedPreferences.setMockInitialValues({});
  });

  group('RL-02 delivery keeps the time guidance', () {
    final now = DateTime.now();
    // Today 20:00 (the evening case) and yesterday (no slot left at all —
    // fails for any time with any lead, so it does not depend on the clock).
    for (final (name, day) in [('today', now), ('yesterday', now.subtract(const Duration(days: 1)))]) {
      testWidgets('delivery $name: no "today no longer possible" line, the earlier guidance stays', (t) async {
        await _form(t, _onDay(day, 'delivery'), _cs('validationDeliveryLeadTime'));
        expect(t.widget<BookingDockV2>(find.byType(BookingDockV2)).blocker, _cs('coBkBlockTime'));
        expect(find.text(_cs('elBkNoTimeLeft')), findsNothing);
        final near = find.byKey(const ValueKey('bk-time-err'));
        expect(t.widget<MgStateBanner>(find.descendant(of: near, matching: find.byType(MgStateBanner))).text,
            isNot(_cs('elBkNoTimeLeft')));
        expect(find.text(_cs('v2BkFixTime')), findsWidgets, reason: 'the red card keeps "fix the time"');
        expect(t.widget<MgCta>(find.byType(MgCta).last).enabled, isFalse, reason: 'the lock stays');
        if (name == 'yesterday') await maybeShot(t, _shot, 'e_last_side__delivery_time__cs__360x780');
        await _done(t);
      });
    }

    testWidgets('branch pickup with no slot left still says "change the dates"', (t) async {
      await _form(t, _onDay(now.subtract(const Duration(days: 1)), 'store'),
          'Na obslužné pobočce je vyzvednutí možné nejdříve za 1 hodinu od teď. Vyberte pozdější čas.');
      expect(t.widget<BookingDockV2>(find.byType(BookingDockV2)).blocker, _cs('elBkNoTimeLeft'));
      await _done(t);
    });
  });

  group('RL-03 swap hint only with a free bike', () {
    testWidgets('all candidates taken → no hint', (t) async {
      await pumpV2(t, _swap(const {'m1': false, 'm2': false}), reducedMotion: true, size: const Size(360, 1400), boundaryKey: _shot);
      expect(find.text(_cs('elSwapPickFirst')), findsNothing);
      await maybeShot(t, _shot, 'e_last_side__swap_all_taken__cs__360x1400');
      expect(t.widget<MgBtnInk>(find.byKey(const ValueKey('swap-v2-confirm'))).onTap, isNull);
    });
    testWidgets('the only free one trailer-blocked → no hint', (t) async {
      await pumpV2(t, _swap(const {'m1': true, 'm2': false}, blocked: (m) => m.id == 'm1'), reducedMotion: true);
      expect(find.text(_cs('elSwapPickFirst')), findsNothing);
    });
    testWidgets('one free → hint', (t) async {
      await pumpV2(t, _swap(const {'m1': true, 'm2': false}), reducedMotion: true, size: const Size(360, 1400), boundaryKey: _shot);
      expect(find.text(_cs('elSwapPickFirst')), findsOneWidget);
      await maybeShot(t, _shot, 'e_last_side__swap_one_free__cs__360x1400');
    });
    testWidgets('availability loading → no hint', (t) async {
      await pumpV2(t, _swap(const {}, loading: true), reducedMotion: true);
      expect(find.text(_cs('elSwapPickFirst')), findsNothing);
      await pumpV2(t, _swap(const {'m1': true}, loading: true), reducedMotion: true);
      expect(find.text(_cs('elSwapPickFirst')), findsNothing);
    });
  });

  testWidgets('RL-04 empty value without opt-in keeps label + value; opt-in is one line', (t) async {
    await pumpV2(t, const Column(children: [
      ResDetailRowV2(label: 'Zrušil', value: ''),
      ResDetailRowV2(label: 'supermoto – Velké Němčice', value: '', line: true),
      ResDetailRowV2(label: 'Délka', value: '3 dny'),
    ]), boundaryKey: _shot);
    await maybeShot(t, _shot, 'e_last_side__detail_rows__cs__360x780');
    final plain = find.ancestor(of: find.text('Zrušil'), matching: find.byType(Row));
    expect(plain, findsWidgets, reason: 'label and value columns as before K4-12');
    expect(find.descendant(of: plain.first, matching: find.byType(Text)), findsNWidgets(2));
    expect(find.ancestor(of: find.text('supermoto – Velké Němčice'), matching: find.byType(Row)), findsNothing);
  });
}
