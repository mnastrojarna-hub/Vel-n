// Last fixes "e_last" (2026-11-13), new look only, display and guidance:
// K4-01 a start day with no pickup time left says "change the dates" and
// "Ukázat proč" lands on Termín (the lock and the error stay); K4-03 an
// empty filter with other bookings says where they are, "show all" is a
// real button above REZERVOVAT; K4-04 the locked swap confirm says what
// comes first; K4-05 the Home REZERVOVAT is secondary while an unpaid
// booking waits (same tap); K4-06 empty licence categories open the form;
// K4-10 the edit calendar legend's "Obsazeno" is hatched like the taken
// days; K4-12 the detail shows the length once and the category – branch
// line full width.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/core/v2/calendar/trip_calendar_parts.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/states/mg_state_banner.dart';
import 'package:motogo_app/core/v2/widgets/mg_buttons.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/booking/v2/booking_date_v2.dart';
import 'package:motogo_app/features/booking/v2/booking_dock_v2.dart';
import 'package:motogo_app/features/booking/v2/booking_form_view_v2.dart';
import 'package:motogo_app/features/booking/v2/booking_sync_v2.dart' show BookingErrKind;
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/home/v2/home_funnel_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_detail_bits_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_swap_v2.dart';
import 'package:motogo_app/features/reservations/v2/reservations_screen_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_booking.dart';
import '../support/fakes_home.dart' show homeOverrides, kMotos, registerHomeStrings;
import '../support/fakes_reservations.dart';
import '../support/v2_harness.dart';

String _cs(String k) => translations['cs']![k]!;
final _shot = GlobalKey();

const _bd = PriceBreakdown(
    basePrice: 12261, extrasTotal: 0, pickupDeliveryFee: 0, returnDeliveryFee: 0, discountTotal: 368, total: 11893, days: 3);

Future<void> _form(WidgetTester t, BookingDraft draft) async {
  await pumpV2(
    t,
    BookingFormV2View(
      moto: kBmw,
      draft: draft,
      bd: _bd,
      pricedExtras: const [],
      err: 'Na obslužné pobočce je vyzvednutí možné nejdříve za 1 hodinu od teď. Vyberte pozdější čas.',
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

Widget _swap({String? selected, List<Motorcycle>? list}) => SingleChildScrollView(
      child: SwapMotoViewV2(
        rangeText: 'Termín rezervace: 1.12.2026 – 5.12.2026',
        dateText: '2.12.2026',
        onPickDate: () {},
        timePicker: const SizedBox(height: 10),
        currentMotoName: 'Husqvarna 701 SM',
        branchFilter: const SizedBox.shrink(),
        motos: AsyncValue.data(list ?? [_moto('m1', 'BMW R 1250 GS'), _moto('m2', 'Honda Africa Twin')]),
        candidates: (l) => l,
        avail: const {'m1': true, 'm2': false},
        availLoading: false,
        selectedId: selected,
        trailerBlocked: (_) => false,
        onTapMoto: (_, __) {},
        net: selected == null ? null : 350,
        netLoading: false,
        saving: false,
        canConfirm: selected != null,
        onConfirm: () {},
      ),
    );

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerBookingStrings();
    registerReservationStrings();
    registerHomeStrings();
    mockBookingPathProvider();
  });
  setUp(() {
    MgMotion.resetSession();
    SharedPreferences.setMockInitialValues({});
  });

  group('K4-01 no pickup time left on the start day', () {
    testWidgets('dock + red card say "change the dates", "Ukázat proč" lands on Termín; lock unchanged', (t) async {
      final y = DateTime.now().subtract(const Duration(days: 1));
      final start = DateTime(y.year, y.month, y.day);
      final draft = bookingDraft(kBmw).copyWith(startDate: () => start, endDate: () => start.add(const Duration(days: 2)));
      await _form(t, draft);
      expect(t.widget<BookingDockV2>(find.byType(BookingDockV2)).blocker, _cs('elBkNoTimeLeft'));
      final near = find.byKey(const ValueKey('bk-time-err'));
      expect(t.widget<MgStateBanner>(find.descendant(of: near, matching: find.byType(MgStateBanner))).text,
          _cs('elBkNoTimeLeft'));
      expect(t.widget<MgCta>(find.byType(MgCta).last).enabled, isFalse, reason: 'the lock stays');
      await t.drag(find.byType(Scrollable).first, const Offset(0, -2400));
      await t.pump(const Duration(milliseconds: 400));
      final why = find.descendant(
          of: find.byType(BookingDockV2),
          matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.label == _cs('coBkShowWhy')));
      await t.tap(why);
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
      expect(find.byType(BookingDateCardV2).hitTestable(), findsOneWidget);
      await maybeShot(t, _shot, 'e_last__booking_no_time_left__cs__360x780');
      await _done(t);
    });

    testWidgets('a later day keeps "Změň čas vyzvednutí"', (t) async {
      await _form(t, bookingDraft(kBmw));
      expect(t.widget<BookingDockV2>(find.byType(BookingDockV2)).blocker, _cs('coBkBlockTime'));
      await _done(t);
    });
  });

  testWidgets('K4-03 empty filter with other bookings: true line, "show all" button above REZERVOVAT', (t) async {
    final list = [resv('a1', status: 'reserved', from: 3, to: 5)];
    await pumpV2(t, const ReservationsScreenV2(),
        size: const Size(360, 1400), overrides: resOverrides(list: list, filter: 'dokoncene'));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text(_cs('noReservations')), findsOneWidget);
    expect(find.text(_cs('elNoResInFilter')), findsOneWidget);
    expect(find.text(_cs('noReservationsDesc')), findsNothing);
    final all = find.byKey(const ValueKey('ea-show-all'));
    expect(t.widget(all), isA<MgBtnGhostDark>());
    final cta = find.byWidgetPredicate((w) => w is MgCta && w.label == _cs('noResBookCta'));
    expect(t.getTopLeft(all).dy, lessThan(t.getTopLeft(cta).dy));
    await t.pump(const Duration(seconds: 2));
  });

  group('K4-04 locked swap confirm', () {
    testWidgets('no bike chosen → the reason above the locked button', (t) async {
      await pumpV2(t, _swap(), reducedMotion: true);
      expect(find.text(_cs('elSwapPickFirst')), findsOneWidget);
      expect(t.widget<MgBtnInk>(find.byKey(const ValueKey('swap-v2-confirm'))).onTap, isNull);
    });
    testWidgets('a bike chosen → no hint; no bike at all → no hint', (t) async {
      await pumpV2(t, _swap(selected: 'm1'), reducedMotion: true);
      expect(find.text(_cs('elSwapPickFirst')), findsNothing);
      await pumpV2(t, _swap(list: const []), reducedMotion: true);
      expect(find.text(_cs('elSwapPickFirst')), findsNothing);
    });
  });

  group('K4-05 Home REZERVOVAT while an unpaid booking waits', () {
    for (final unpaid in [true, false]) {
      testWidgets('unpaid=$unpaid', (t) async {
        final pending = unpaid ? PendingBooking(id: 'b1', totalPrice: 11893, createdAt: DateTime.now()) : null;
        await pumpV2(t, const SingleChildScrollView(child: HomeFunnelV2()),
            overrides: homeOverrides(funnel: kMotos.take(2).toList(), pending: pending));
        for (var i = 0; i < 20; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        final ghost = find.byKey(const ValueKey('home-funnel-reserve-ghost'));
        expect(ghost, unpaid ? findsOneWidget : findsNothing);
        expect(find.descendant(of: find.byType(HomeFunnelV2), matching: find.byType(MgCta)),
            unpaid ? findsNothing : findsOneWidget);
        if (unpaid) expect(t.widget<MgBtnGhostDark>(ghost).onTap, isNotNull, reason: 'same tap, still enabled');
        expect(t.takeException(), isNull);
        await _done(t);
      });
    }
  });

  group('K4-10 legend', () {
    testWidgets('hatchBusy draws the hatch; the default stays the plain swatch', (t) async {
      await pumpV2(t, const TripLegend(items: [TripLegendKind.busy], hatchBusy: true));
      expect(find.byKey(const ValueKey('trip-legend-busy-hatch')), findsOneWidget);
      await pumpV2(t, const TripLegend(items: [TripLegendKind.busy]));
      expect(find.byKey(const ValueKey('trip-legend-busy-hatch')), findsNothing);
    });
  });

  testWidgets('K4-12 the opted-in row (RL-04) is one full-width line; with a value label + value', (t) async {
    await pumpV2(t, const Column(children: [
      ResDetailRowV2(label: 'supermoto – Velké Němčice', value: '', line: true),
      ResDetailRowV2(label: 'Délka', value: '3 dny'),
    ]));
    final line = find.text('supermoto – Velké Němčice');
    expect(find.ancestor(of: line, matching: find.byType(Row)), findsNothing);
    expect(find.ancestor(of: find.text('Délka'), matching: find.byType(Row)), findsWidgets);
  });
}
