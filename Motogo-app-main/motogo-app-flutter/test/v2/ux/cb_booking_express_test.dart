// Booking form v2 after lookonly-fix (owner 2026-11-07 "jen upgrade
// vzhledu"): the OLD single scroll — every section open, no folds, no dock
// fix / breakdown links; the validation banner keeps its fixing actions
// (R2 meaningful states) and they bring the offending input on screen.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/booking_form_extras_section.dart';
import 'package:motogo_app/core/booking_form_time_section.dart';
import 'package:motogo_app/core/booking_form_widget.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/booking/booking_provider.dart';
import 'package:motogo_app/features/booking/v2/booking_consents_v2.dart';
import 'package:motogo_app/features/booking/v2/booking_date_v2.dart';
import 'package:motogo_app/features/booking/v2/booking_dock_v2.dart';
import 'package:motogo_app/features/booking/v2/booking_recap_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_booking.dart';
import '../support/v2_harness.dart';

final _cs = AppTranslations.of('cs');

Future<ProviderContainer> _form(WidgetTester t, List<Override> o, {Size size = const Size(360, 780)}) async {
  await pumpV2(t, const BookingDebugWrapper(), size: size, overrides: o, reducedMotion: true);
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
  return ProviderScope.containerOf(t.element(find.byType(BookingDebugWrapper)));
}

Future<void> _done(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 2));
}

/// [f] lies (at least partly) inside the screen between the header and the dock.
void _expectOnScreen(WidgetTester t, Finder f) {
  expect(f, findsWidgets);
  final r = t.getRect(f.first);
  final screen = t.view.physicalSize / t.view.devicePixelRatio;
  expect(r.bottom > 0 && r.top < screen.height, isTrue, reason: 'rect $r off screen');
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

  testWidgets('returning customer: every section open at once (old form), CTA live in the dock', (t) async {
    await _form(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw)));
    expect(find.byType(BookingDateCardV2), findsOneWidget);
    expect(find.byType(BookingFormTimeSection), findsOneWidget);
    expect(find.byType(BookingFormExtrasSection), findsOneWidget);
    expect(find.byType(BookingRecapV2), findsOneWidget);
    expect(find.byType(BookingConsentsV2), findsOneWidget);
    final dock = t.widget<BookingDockV2>(find.byType(BookingDockV2));
    expect(dock.trailingLabel, isNull);
    final cta = find.byType(MgCta);
    expect(t.widget<MgCta>(cta).enabled, isTrue);
    expect(t.getRect(cta).bottom, lessThanOrEqualTo(780));
    await _done(t);
  });

  testWidgets('consents off: the dock names the blocker (old hint), "Ukázat proč" (J1), no "Opravit" link', (t) async {
    await _form(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw, consents: false)));
    final dock = t.widget<BookingDockV2>(find.byType(BookingDockV2));
    expect(dock.blocker, _cs.tr('v2BkBlockConsent'));
    // J1 (clarity order): a locked CTA always offers "Ukázat proč" → the reason.
    expect(dock.trailingLabel, _cs.tr('v2BkShowWhy'));
    expect(dock.onTrailing, isNotNull);
    expect(find.text(_cs.tr('v2BkFix')), findsNothing);
    await _done(t);
  });

  for (final kind in ['dates', 'time']) {
    testWidgets('BookingErrKind.$kind: the banner action brings the offending input on screen', (t) async {
      const msg = 'Chyba ve formuláři';
      final o = [
        ...bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw)),
        bookingValidationErrorProvider.overrideWith((ref) => msg),
        if (kind == 'dates') overlapValidationProvider.overrideWith((ref) => msg),
        if (kind == 'time') pickupLeadTimeValidationProvider.overrideWith((ref) => msg),
      ];
      await _form(t, o);
      final action = find.text(_cs.tr(kind == 'dates' ? 'psChangeDates' : 'v2BkFixTime'));
      await t.ensureVisible(action.last);
      await t.pump();
      await t.tap(action.last, warnIfMissed: false);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(milliseconds: 400));
      _expectOnScreen(t, kind == 'dates' ? find.byType(BookingDateCardV2) : find.byType(BookingFormTimeSection));
      await _done(t);
    });
  }
}
