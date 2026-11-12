// fix:r1:areas — owner 2026-11-07 "Pozor ať neomezíš nikde funkčnost":
// v2 views that had dropped / hidden something the old look offered, and
// the edit / SOS / date surfaces that were still the old look inside v2.
// Every test drives the SAME callbacks the old widgets used.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/motion/mg_anim.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/tokens/mg_colors.dart';
import 'package:motogo_app/features/auth/v2/date_field_v2.dart';
import 'package:motogo_app/features/booking/v2/address_option_v2.dart';
import 'package:motogo_app/features/booking/v2/booking_recap_v2.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/payment/v2/pay_dock_v2.dart';
import 'package:motogo_app/features/reservations/v2/page_swipe_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_filter_tabs_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_moto_rows_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_sizes_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_swap_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_swap_date_sheet_v2.dart';
import 'package:motogo_app/features/routes/animated_route_icon.dart';
import 'package:motogo_app/features/sos/v2/sos_here_address_v2.dart';

import '../support/fakes_reservations.dart';
import '../support/v2_harness.dart';

Motorcycle _moto(String id, String model, {String branchType = 'obslužná'}) => Motorcycle.fromJson({
      'id': id,
      'model': model,
      'brand': model.split(' ').first,
      'category': 'cestovni',
      'status': 'active',
      'branches': {'name': 'Mezná', 'type': branchType},
      'license_required': 'A',
      'images': ['https://example.com/$id-1.jpg', 'https://example.com/$id-2.jpg'],
      'price_mon': 2000,
      'price_tue': 2000,
      'price_wed': 2000,
      'price_thu': 2000,
      'price_fri': 2000,
      'price_sat': 2000,
      'price_sun': 2000,
    });

void main() {
  setUpAll(loadMontserrat);
  setUp(MgMotion.resetSession);

  testWidgets('SOS light pay dock keeps the old verifying texts (do not pay again)', (t) async {
    await pumpV2(
      t,
      Align(
        alignment: Alignment.bottomCenter,
        child: PayDockV2(
          contextLine: 'K zaplacení · 500 Kč',
          label: 'ZAPLATIT',
          price: '500 Kč',
          enabled: true,
          busy: true,
          onPay: () {},
          status: 'Ověřujeme platbu',
          statusNote: 'Neplať znovu',
          rank: false,
        ),
      ),
      reducedMotion: true,
    );
    expect(find.text('Ověřujeme platbu'), findsOneWidget);
    expect(find.text('Neplať znovu'), findsOneWidget);
  });

  group('V2PageSwipe (page-wide segment swipe, same thresholds)', () {
    Future<List<int>> run(WidgetTester t, Future<void> Function(Finder) gesture) async {
      final steps = <int>[];
      await pumpV2(
        t,
        V2PageSwipe(
          onStep: (d) {
            steps.add(d);
            return true;
          },
          child: const SizedBox.expand(child: ColoredBox(color: Color(0xFFEEEEEE), child: Text('header'))),
        ),
      );
      await gesture(find.text('header'));
      await t.pumpAndSettle();
      return steps;
    }

    testWidgets('fling left = next, fling right = previous', (t) async {
      expect(await run(t, (f) => t.fling(f, const Offset(-200, 0), 900)), [1]);
      expect(await run(t, (f) => t.fling(f, const Offset(200, 0), 900)), [-1]);
    });

    testWidgets('slow drag past 72 px commits; a short one does not', (t) async {
      expect(await run(t, (f) => t.drag(f, const Offset(-90, 0))), [1]);
      expect(await run(t, (f) => t.drag(f, const Offset(-40, 0))), isEmpty);
    });
  });

  group('Výměna motorky v2 (same state + callbacks)', () {
    final free = _moto('m1', 'BMW R 1250 GS');
    final busy = _moto('m2', 'Honda Africa Twin');
    final self = _moto('m3', 'KTM 890 Adventure', branchType: 'samoobslužná');

    Widget view({
      required List<String> log,
      String? selected,
      bool canConfirm = false,
      bool trailer = false,
    }) =>
        SingleChildScrollView(
          child: SwapMotoViewV2(
            rangeText: 'Termín rezervace: 1.12.2026 – 5.12.2026',
            dateText: '2.12.2026',
            onPickDate: () => log.add('date'),
            timePicker: const SizedBox(height: 10),
            currentMotoName: 'Husqvarna 701 SM',
            branchFilter: const SizedBox.shrink(),
            motos: AsyncValue.data([free, busy, self]),
            candidates: (l) => l,
            avail: const {'m1': true, 'm2': false, 'm3': true},
            availLoading: false,
            selectedId: selected,
            trailerBlocked: (m) => trailer && m.branchType == 'samoobslužná',
            onTapMoto: (m, sel) => log.add('${m.id}:$sel'),
            net: selected == null ? null : 350,
            netLoading: false,
            saving: false,
            canConfirm: canConfirm,
            onConfirm: () => log.add('confirm'),
          ),
        );

    testWidgets('date box = the section\'s own pick; only free, allowed bikes are tappable', (t) async {
      final log = <String>[];
      await pumpV2(t, view(log: log, trailer: true), reducedMotion: true);
      await t.tap(find.byKey(const ValueKey('swap-v2-date')));
      await t.tap(find.text('BMW R 1250 GS'));
      await t.tap(find.text('Honda Africa Twin'), warnIfMissed: false);
      await t.ensureVisible(find.text('KTM 890 Adventure'));
      await t.tap(find.text('KTM 890 Adventure'), warnIfMissed: false);
      expect(log, ['date', 'm1:false']);
      expect(find.text('Obsazeno'), findsOneWidget);
      // Confirm locked exactly when the old button was.
      final cta = find.byKey(const ValueKey('swap-v2-confirm'));
      await t.ensureVisible(cta);
      await t.tap(cta, warnIfMissed: false);
      expect(log, ['date', 'm1:false']);
    });

    testWidgets('chosen bike: price difference + live confirm', (t) async {
      final log = <String>[];
      await pumpV2(t, view(log: log, selected: 'm1', canConfirm: true), reducedMotion: true);
      expect(find.textContaining('350'), findsWidgets);
      final cta = find.byKey(const ValueKey('swap-v2-confirm'));
      await t.ensureVisible(cta);
      await t.tap(cta);
      expect(log, ['confirm']);
    });

    testWidgets('swap date sheet: only the reservation days pick; a pick returns the day', (t) async {
      DateTime? got;
      final first = DateTime(2026, 12, 1), last = DateTime(2026, 12, 5);
      await pumpV2(
        t,
        Builder(
          builder: (c) => TextButton(
            onPressed: () async =>
                got = await showSwapDateSheetV2(c, first: first, last: last, initial: DateTime(2026, 12, 2), title: 'Datum'),
            child: const Text('open'),
          ),
        ),
        reducedMotion: true,
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.byType(SwapDateCalendarV2), findsOneWidget);
      // A day outside the range does nothing.
      await t.tap(find.text('9').first, warnIfMissed: false);
      await t.pumpAndSettle();
      expect(find.byType(SwapDateCalendarV2), findsOneWidget);
      await t.tap(find.text('4').first);
      await t.pumpAndSettle();
      expect(got, DateTime(2026, 12, 4));
      expect(find.byType(SwapDateCalendarV2), findsNothing);
    });
  });

  testWidgets('branch filter chips = the dropdown\'s choice (null = all)', (t) async {
    final got = <String?>[];
    await pumpV2(
      t,
      EditBranchFilterV2(
        branches: const [
          {'id': 'b1', 'name': 'Mezná'},
          {'id': 'b2', 'name': 'Brno'},
        ],
        value: 'b1',
        onChanged: got.add,
      ),
    );
    await t.ensureVisible(find.text('Brno'));
    await t.pumpAndSettle();
    await t.tap(find.text('Brno'));
    await t.ensureVisible(find.text('Mezná'));
    await t.pumpAndSettle();
    await t.tap(find.text('Mezná'));
    await t.ensureVisible(find.textContaining('poboč').first);
    await t.pumpAndSettle();
    await t.tap(find.textContaining('poboč').first);
    expect(got, ['b2', null]);
  });

  testWidgets('edit gear size v2: tap picks, tapping the chosen size clears (old rule)', (t) async {
    final got = <String?>[];
    await pumpV2(
      t,
      EditGearSizePickerV2(label: 'Helma', icon: 'helmet', sizes: const ['S', 'M', 'L'], selectedSize: 'M', onSizeSelected: got.add),
    );
    await t.tap(find.text('L'));
    await t.tap(find.text('M'));
    expect(got, ['L', null]);
  });

  testWidgets('date field v2: the box opens the value sheet; a pick = the same setter', (t) async {
    final days = <int>[], years = <int>[];
    await pumpV2(
      t,
      DateFieldRowV2(
        day: null,
        month: 5,
        year: 1990,
        years: [for (var y = 2008; y >= 1920; y--) y],
        monthNames: const ['Leden', 'Únor', 'Březen', 'Duben', 'Květen', 'Červen', 'Červenec', 'Srpen', 'Září', 'Říjen', 'Listopad', 'Prosinec'],
        hints: const ['Den', 'Měsíc', 'Rok'],
        label: 'Datum narození',
        onDay: days.add,
        onMonth: (_) {},
        onYear: years.add,
      ),
      size: const Size(320, 700),
      reducedMotion: true,
    );
    // One row at 320 dp; the month number is never cut.
    final d = t.getRect(find.byKey(const ValueKey('date-v2-day')));
    final y = t.getRect(find.byKey(const ValueKey('date-v2-year')));
    expect(d.top, y.top);
    expect(find.text('05'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('date-v2-day')));
    await t.pumpAndSettle();
    await t.tap(find.text('07'));
    await t.pumpAndSettle();
    expect(days, [7]);
    await t.tap(find.byKey(const ValueKey('date-v2-year')));
    await t.pumpAndSettle();
    expect(find.text('1920'), findsOneWidget);
    await t.tap(find.text('1990').last);
    await t.pumpAndSettle();
    expect(years, [1990]);
    expect(t.takeException(), isNull);
  });

  testWidgets('address option v2 + SOS "kde jsi" row: same taps', (t) async {
    var taps = 0, here = 0;
    await pumpV2(
      t,
      Column(children: [
        AddressOptionV2(label: 'Na pobočce', sublabel: 'Mezná 9', price: 'zdarma', selected: true, onTap: () => taps++),
        SosHereAddressV2(title: 'Kde právě jsi', sub: 'Klepni', busy: false, used: false, onTap: () => here++),
      ]),
    );
    await t.tap(find.text('Na pobočce'));
    await t.tap(find.text('Kde právě jsi'));
    expect([taps, here], [1, 1]);
  });

  testWidgets('payment recap: the photo opens the bike\'s photos (old gallery card)', (t) async {
    var opened = 0;
    await pumpV2(t, BookingRecapV2(moto: _moto('m1', 'BMW R 1250 GS'), photoCount: 2, onPhotoTap: () => opened++));
    expect(find.text('2'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('bk-recap-photo')));
    expect(opened, 1);
    expect(find.byType(MgPress), findsWidgets);
  });

  testWidgets('route icon (v2 once): reduced motion = end state at once, no running animation', (t) async {
    await pumpV2(t, const Center(child: AnimatedRouteIcon(once: true)), reducedMotion: true);
    await t.pump();
    expect(t.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('Rezervace filter: ONE thumb slides with the finger; one light label at a time', (t) async {
    final p = ValueNotifier<double>(0);
    await pumpV2(
      t,
      ResFilterTabsV2(value: 'all', counts: const {'all': 3}, onSelect: (_) {}, onStep: (_) {}, dragProgress: p),
      reducedMotion: true,
      // fix:r2 — the single-row track (with its thumb) only where all 5
      // tabs fit; narrower phones wrap them (tested in fix_r2_areas_test).
      size: const Size(600, 780),
    );
    await t.pump();
    final thumb = find.byKey(const ValueKey('res-filter-thumb'));
    expect(thumb, findsOneWidget);
    final x0 = t.getRect(thumb).left;
    p.value = 0.6;
    await t.pump();
    await t.pump();
    expect(thumb, findsOneWidget);
    final x1 = t.getRect(thumb).left;
    expect(x1, greaterThan(x0));
    // Exactly one label is white (the thumb is mostly under the 2nd tab).
    final light = t
        .widgetList<AnimatedDefaultTextStyle>(
            find.descendant(of: find.byType(ResFilterTabsV2), matching: find.byType(AnimatedDefaultTextStyle)))
        .where((w) => w.style.color == MgColors.onDark);
    expect(light.length, 1);
    p.value = 0;
    await t.pump();
    await t.pump();
    expect(t.getRect(thumb).left, x0);
  });
}
