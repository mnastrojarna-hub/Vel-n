// lookonly-fix:areas (owner 2026-11-07 "jen upgrade vzhledu"): the v2 look
// of Motorky, the moto detail, the booking form and its time card shows the
// SAME content, actions and defaults as the original (flag OFF) screens.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/booking_form_widget.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/states/mg_support_row.dart';
import 'package:motogo_app/features/booking/v2/booking_dock_v2.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_detail_page.dart';
import 'package:motogo_app/features/catalog/v2/moto_card_full_v2.dart';
import 'package:motogo_app/features/catalog/v2/moto_filter_card_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_dates_card_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';
import 'package:motogo_app/features/catalog/moto_model.dart' show BookedDateRange;
import 'package:motogo_app/features/catalog/widgets/availability_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_booking.dart';
import '../support/fakes_catalog.dart';
import '../support/v2_harness.dart';

String _cs(String key) => AppTranslations.of('cs').tr(key);

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

  final (ws, we) = futureWeekend();

  group('Motorky = the old search screen', () {
    testWidgets('dates + calendar and the filter panel inline, the old count line, Detail CTA', (t) async {
      await pumpV2(t, const MotorkyScreenV2(),
          size: const Size(412, 3000),
          overrides: catalogOverrides(filter: CatalogFilter(startDate: ws, endDate: we), filtered: [kBmw, kHusq]));
      await t.pump(const Duration(milliseconds: 800));
      // Inline, always open: the step line, the single-day hint, the calendar.
      expect(find.byType(MotorkyDatesCardV2), findsOneWidget);
      // M3-14: the same single-day hint, in the informal v2 text.
      expect(find.text(_cs('v2BkSingleDayHint')), findsOneWidget);
      expect(find.descendant(of: find.byType(MotorkyDatesCardV2), matching: find.byType(AvailabilityCalendar)),
          findsOneWidget);
      // The shared filter panel inline (folded as before).
      expect(find.byType(MotoFilterCardV2), findsOneWidget);
      // The old results header.
      expect(find.textContaining(_cs('searchAvailableMotorcycles').replaceAll('{n}', '2')), findsOneWidget);
      // No grid toggle; the card button is the old "Detail" (its tap →
      // /moto/:id is covered in catalog_card_book_test).
      final card = t.widget<MotoCardFullV2>(find.byType(MotoCardFullV2).first);
      expect(card.ctaLabel, _cs('motoCardDetail'));
      expect(card.onCta, isNull);
      expect(find.text(_cs('v2CatCtaBook').toUpperCase()), findsNothing);
    });

    testWidgets('the header has the always visible back', (t) async {
      await pumpV2(t, const MotorkyScreenV2(), size: const Size(360, 1600), overrides: catalogOverrides());
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey('motorky-back')), findsOneWidget);
      expect(find.byKey(const ValueKey('motorky-menu')), findsOneWidget);
    });

    testWidgets('the filter card starts folded and opens on tap (old panel)', (t) async {
      await pumpV2(t, const MotorkyScreenV2(), size: const Size(412, 3000), overrides: catalogOverrides());
      await t.pump(const Duration(milliseconds: 600));
      expect(t.widget<MotoFilterCardV2>(find.byType(MotoFilterCardV2)).open, isFalse);
      await t.tap(find.text(_cs('homeFilterTitle')));
      await t.pump(const Duration(milliseconds: 400));
      expect(t.widget<MotoFilterCardV2>(find.byType(MotoFilterCardV2)).open, isTrue);
    });
  });

  group('moto detail = the old detail', () {
    testWidgets('full description, parameters and price list open; branch with city; no presets', (t) async {
      await pumpV2(t, const MotoDetailPage(motoId: 'm-bmw', showBackButton: true),
          size: const Size(412, 5000), overrides: catalogOverrides());
      await t.pump(const Duration(milliseconds: 800));
      final desc = t.widget<Text>(find.byKey(const ValueKey('det-desc')));
      expect(desc.maxLines, isNull);
      expect(find.text(_cs('v2UxCbFullDesc')), findsNothing);
      // Parameters + day prices visible without a tap (section titles, no toggles).
      expect(find.text(_cs('v2DetAllParams')), findsOneWidget);
      expect(find.text(_cs('v2DetPriceByDay')), findsOneWidget);
      // Branch "{name}, {city}" (old hero + "Pobočka:" line).
      expect(find.textContaining('Mezná, Pelhřimov'), findsWidgets);
      expect(find.byKey(const ValueKey('det-branch')), findsOneWidget);
      // No weekend presets (the old detail had none).
      expect(find.text(_cs('v2CatPresetWeekend')), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
    });
  });

  group('booking form = the old form', () {
    Future<void> pumpForm(WidgetTester t, List<Override> overrides) async {
      await pumpV2(t, const BookingDebugWrapper(), size: const Size(412, 5000), overrides: overrides);
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
    }

    testWidgets('every section open, no folds / steps / support row; dock without extra links', (t) async {
      await pumpForm(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw)));
      expect(find.byType(MgSupportRow), findsNothing);
      // Moto card: "od {price}" + the branch WITH its city.
      expect(find.textContaining('Mezná, Pelhřimov'), findsOneWidget);
      // Times, pickup / return and extras sections are on the page at once.
      expect(find.text(_cs('v2BkPickupTime')), findsWidgets);
      expect(find.text(_cs('v2BkGearTitle')), findsOneWidget);
      final dock = t.widget<BookingDockV2>(find.byType(BookingDockV2));
      expect(dock.trailingLabel, isNull);
      expect(dock.onTrailing, isNull);
      expect(dock.context2, isNot(contains(_cs('v2UxCbDockSaves').split(' ').first)));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
    });

    testWidgets('time card: the old single hint, no "Nastavit 12:00", no ½ marks', (t) async {
      await pumpForm(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw)));
      expect(find.text(_cs('latePickupHint12')), findsOneWidget);
      expect(find.text(_cs('v2CalcLateSet')), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
    });

    testWidgets('time card at a self-service branch: the old ssPickupHint (both looks)', (t) async {
      final o = bookingOverrides(moto: kHusq, draft: bookingDraft(kHusq));
      await pumpForm(t, o);
      expect(find.text(_cs('ssPickupHint')), findsOneWidget);
      expect(find.text(_cs('v2LpSsHint')), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
      await pumpV2(t, const BookingDebugWrapper(), size: const Size(412, 5000), overrides: o, v2: false);
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('🌗 ${_cs('ssPickupHint')}'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
    });
  });

  testWidgets('calendar: a busy day does not react (no toast), as in the original', (t) async {
    final now = DateTime.now();
    final base = DateTime(now.year, now.month + 1, 1);
    DateTime day(int d) => DateTime(base.year, base.month, d);
    final out = <(DateTime, DateTime)>[];
    await pumpV2(
      t,
      SingleChildScrollView(
        child: AvailabilityCalendar(
          selectedStart: day(2),
          selectedEnd: day(3),
          bookedDates: [BookedDateRange(start: day(10), end: day(10), status: 'confirmed')],
          onRangeSelected: (s, e) => out.add((s, e)),
        ),
      ),
      size: const Size(412, 915),
      reducedMotion: true,
    );
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('10').first, warnIfMissed: false);
    await t.pump();
    await t.pump(const Duration(milliseconds: 350));
    expect(find.text(_cs('v2UxCbBusyDay')), findsNothing);
    expect(out, isEmpty);
    await t.pump(const Duration(seconds: 5));
  });
}
