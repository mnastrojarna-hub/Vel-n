// Rezervační formulář: „Pokračovat k platbě“ jen se ZNÁMOU obsazeností
// motorky. Načítá se → tlačítko zamčené bez červeného řádku; selhalo →
// zamčené, červený řádek / banner s „Zkusit znovu“ a chybová karta
// kalendáře; po úspěšném opakování odemčené. Oba vzhledy (stejné pravidlo).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/booking_form_widget.dart';
import 'package:motogo_app/core/feature_flags.dart' show selfServiceDeliveryEnabledProvider;
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/auth/auth_provider.dart';
import 'package:motogo_app/features/booking/booking_provider.dart';
import 'package:motogo_app/features/booking/v2/booking_dock_v2.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/loyalty/loyalty_provider.dart';
import 'package:motogo_app/features/reservations/reservation_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'v2/support/fakes_booking.dart';
import 'v2/support/v2_harness.dart';

String _cs(String k) => translations['cs']![k]!;

enum _Mode { loading, error, ok }

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerBookingStrings();
    mockBookingPathProvider();
  });
  setUp(() {
    MgMotion.resetSession();
    SharedPreferences.setMockInitialValues({});
  });

  for (final v2 in [false, true]) {
    final look = v2 ? 'new look' : 'old look';
    var mode = _Mode.loading;
    var calls = 0;

    List<Override> overrides() => [
          bookingMotoProvider.overrideWith((ref) => kBmw),
          bookingDraftProvider.overrideWith((ref) => bookingDraft(kBmw)),
          profileProvider.overrideWith((ref) async => kProfileOk),
          loyaltyStatusProvider.overrideWith((ref) => Future.value(kLoyalty3)),
          reservationsProvider.overrideWith((ref) => Stream.value(const [])),
          bookedDatesProvider.overrideWith((ref, id) {
            calls++;
            return switch (mode) {
              _Mode.loading => Completer<List<BookedDateRange>>().future,
              _Mode.error => Future<List<BookedDateRange>>.error(Exception('net')),
              _Mode.ok => Future.value(const <BookedDateRange>[]),
            };
          }),
          trailerAvailabilityProvider.overrideWith((ref, r) async => const TrailerAvailability(1, 'tr-1')),
          selfServiceDeliveryEnabledProvider.overrideWith((ref) async => false),
          pickupDelivFeeProvider.overrideWith((ref) => 0),
          pickupDistKmProvider.overrideWith((ref) => 0),
        ];

    Future<void> pump(WidgetTester t) async {
      await pumpV2(t, const BookingDebugWrapper(),
          v2: v2, reducedMotion: true, size: const Size(412, 915), overrides: overrides());
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 300));
      }
    }

    bool ctaEnabled(WidgetTester t) {
      if (v2) return t.widget<BookingDockV2>(find.byType(BookingDockV2)).canProceed;
      final btn = find.ancestor(of: find.text(_cs('proceedToPayment')), matching: find.byType(ElevatedButton));
      return t.widget<ElevatedButton>(btn.first).onPressed != null;
    }

    testWidgets('$look: occupancy still loading → CTA locked, no red row', (t) async {
      mode = _Mode.loading;
      await pump(t);
      expect(ctaEnabled(t), isFalse);
      expect(find.text(_cs('fxBookedDatesWait')), findsNothing);
      expect(find.text(_cs('fxBookedDatesFail')), findsNothing);
    });

    testWidgets('$look: occupancy failed → CTA locked, red row + retry; retry OK → CTA enabled', (t) async {
      mode = _Mode.error;
      calls = 0;
      await pump(t);
      expect(ctaEnabled(t), isFalse);
      expect(find.text(_cs('fxBookedDatesWait')), findsOneWidget);
      if (!v2) {
        // Old look: the date summary is collapsed → open the calendar.
        final edit = find.text(_cs('edit').toUpperCase()).first;
        await t.ensureVisible(edit);
        await t.pump();
        await t.tap(edit);
        await t.pump(const Duration(milliseconds: 400));
      }
      expect(find.text(_cs('fxBookedDatesFail')), findsWidgets, reason: 'calendar error card');
      final retry = find.text(_cs('eoRetry'));
      expect(retry, findsWidgets);
      // The retry next to the red row / in the banner (the last one on the page).
      mode = _Mode.ok;
      final before = calls;
      final target = find.ancestor(of: find.text(_cs('fxBookedDatesWait')), matching: find.byType(Row)).evaluate().isNotEmpty && !v2
          ? find.descendant(
              of: find.ancestor(of: find.text(_cs('fxBookedDatesWait')), matching: find.byType(Row)).first,
              matching: find.text(_cs('eoRetry')))
          : retry.last;
      await t.ensureVisible(target);
      await t.pump();
      await t.tap(target);
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 300));
      }
      expect(calls, greaterThan(before), reason: 'retry asked again');
      expect(find.text(_cs('fxBookedDatesWait')), findsNothing);
      expect(ctaEnabled(t), isTrue);
    });
  }
}
