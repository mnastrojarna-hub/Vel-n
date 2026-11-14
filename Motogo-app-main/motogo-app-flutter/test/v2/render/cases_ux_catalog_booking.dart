// verify:render cases — catalog_booking package (v2 on every page,
// 2026-11-07): compact Motorky bar, list skeleton, filter sheet with an
// active filter, bike pager pill, fullscreen gallery viewer, booking
// express (folded / opened), size sheets, promo sheet, time sheet, busy
// range note. MG_VERIFY_RENDER=1 flutter test
// test/v2/render/render_ux_catalog_booking_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/booking_form_widget.dart';
import 'package:motogo_app/core/v2/motion/mg_anim.dart';
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/booking/my_vouchers.dart';
import 'package:motogo_app/features/booking/v2/sections/extras_rows_v2.dart';
import 'package:motogo_app/features/booking/v2/sections/promo_v2.dart';
import 'package:motogo_app/features/booking/v2/time_sheet_v2.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_detail_screen.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';
import 'package:motogo_app/features/catalog/widgets/availability_calendar.dart';
import 'package:motogo_app/features/catalog/widgets/fullscreen_gallery.dart';

import '../support/fakes_booking.dart';
import '../support/fakes_catalog.dart';
import 'render_harness.dart';

Future<void> _tapIn(WidgetTester t, Finder f) async {
  // Mid-viewport: at the top edge it would sit under the pinned back bar.
  await Scrollable.ensureVisible(t.element(f), alignment: 0.4);
  await t.pump();
  await t.tap(f, warnIfMissed: false);
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

Future<void> _scrollList(WidgetTester t) async {
  await t.drag(find.byType(CustomScrollView).first, const Offset(0, -700));
  await t.pump(const Duration(milliseconds: 500));
}

Future<void> _gallery(WidgetTester t) async {
  FullscreenGallery.open(t.element(find.byType(MotoDetailScreen)), images: const ['', ''], initialIndex: 1);
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
}

Future<void> _busyRange(WidgetTester t) async {
  for (final d in ['8', '12']) {
    await t.tap(find.text(d).first, warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 350));
  }
}

List<RenderCase> uxCatalogBookingRenderCases() {
  final (ws, we) = futureWeekend();
  final dated = CatalogFilter(startDate: ws, endDate: we);
  final passenger = SelectedExtra(
      id: 'extra-spolujezdec', name: 'Výbava spolujezdce', price: 0, size: 'Helma: L, Rukavice: M, Bunda: XL, Kalhoty: L');
  final gear = {
    ...kProfileOk,
    'gear_sizes': {
      'rider': {'helmet': 'M', 'boots': '43'},
      'passenger': {'helmet': 'L', 'gloves': 'M', 'jacket': 'XL', 'pants': 'L'},
    },
  };
  final now = DateTime.now();
  final base = DateTime(now.year, now.month + 1, 1);
  DateTime day(int d) => DateTime(base.year, base.month, d);
  RenderCase cat(String state, List<Override> Function() o, {Widget Function()? build, Future<void> Function(WidgetTester)? after, bool loading = false}) =>
      RenderCase('uxcb', 'catalog', state, build ?? () => const MotorkyScreenV2(), o, after: after, loading: loading);
  RenderCase bk(String state, List<Override> Function() o, {Future<void> Function(WidgetTester)? after}) =>
      RenderCase('uxcb', 'booking', state, () => const BookingDebugWrapper(), o, after: after);
  return [
    cat('compact_bar', () => catalogOverrides(filter: dated, filtered: [kBmw, kHusq, kKids]), after: _scrollList),
    cat('pager_pill', () => [...catalogOverrides(filter: dated), filteredMotoIdsProvider.overrideWith((ref) => ['m-bmw', 'm-husq', 'm-shot'])],
        build: () => const MotoDetailScreen(motoId: 'm-husq')),
    cat('gallery', () => [...catalogOverrides(), filteredMotoIdsProvider.overrideWith((ref) => ['m-bmw', 'm-husq'])],
        build: () => const MotoDetailScreen(motoId: 'm-bmw'), after: _gallery),
    cat('busy_range', () => const [], build: () => SingleChildScrollView(
          child: AvailabilityCalendar(
            selectedStart: day(2),
            selectedEnd: day(3),
            bookedDates: [BookedDateRange(start: day(10), end: day(10), status: 'confirmed')],
            onRangeSelected: (_, __) {},
          ),
        ), after: _busyRange),
    bk('express_folded', () => bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw, extras: [passenger]))),
    bk('express_open', () => bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw))),
    bk('sizes_sheet', () => [
          ...bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw), profile: gear),
          myVouchersProvider.overrideWith((ref) async => const <MyVoucher>[]),
        ], after: (t) async {
      await _tapIn(t, find.byType(BookingExtraRowV2).at(0));
    }),
    bk('boots_sheet', () => bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw), profile: gear), after: (t) async {
      await _tapIn(t, find.byType(BookingExtraRowV2).at(1));
    }),
    bk('promo_sheet', () => [
          ...bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw)),
          myVouchersProvider.overrideWith((ref) async => const [MyVoucher(code: 'DAR1000', amount: 1000)]),
        ], after: (t) => _tapIn(t, find.descendant(of: find.byType(BookingPromoV2), matching: find.byType(MgPress)).first)),
    bk('time_sheet', () => bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw)), after: (t) async {
      await _tapIn(t, find.byType(TimeFieldV2).first);
    }),
  ];
}
