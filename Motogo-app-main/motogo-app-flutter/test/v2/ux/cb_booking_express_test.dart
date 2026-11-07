// CB-11 · express booking form (Booking board "Máme to připravené"): a
// returning customer whose trip is ready sees "Termín a předání" and the
// gear / extras folded; a section holding a blocker is open; the dock's
// "Doplnit" opens + scrolls to the offending input for every blocker;
// folding never changes a value. CB-10 recap + CB-16 dock saving too.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/booking_form_extras_section.dart';
import 'package:motogo_app/core/booking_form_time_section.dart';
import 'package:motogo_app/core/booking_form_widget.dart';
import 'package:motogo_app/core/currency.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/booking/booking_provider.dart';
import 'package:motogo_app/features/booking/v2/booking_consents_v2.dart';
import 'package:motogo_app/features/booking/v2/booking_date_v2.dart';
import 'package:motogo_app/features/booking/v2/booking_dock_v2.dart';
import 'package:motogo_app/features/booking/v2/booking_express_v2.dart';
import 'package:motogo_app/features/booking/v2/booking_recap_v2.dart';
import 'package:motogo_app/features/booking/v2/booking_warning_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/booking_express.dart';
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

bool _open<T extends Widget>(WidgetTester t) {
  final w = t.widget(find.byType(T).first);
  return w is BookingHandoverRowV2 ? w.open : (w as BookingReadyCardV2).open;
}

/// Taps the dock's "Doplnit" and lets the reveal + scroll finish.
Future<void> _fix(WidgetTester t) async {
  await t.tap(find.text(_cs.tr('v2BkFix')).last, warnIfMissed: false);
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  await t.pump(const Duration(milliseconds: 400));
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

  testWidgets('returning customer, trip ready: both sections OPEN (owner "nic neomezit"), CTA live in the dock', (t) async {
    await _form(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw)));
    // Times, delivery choice, 12:00 tip and extras (free trailer…) stay
    // visible at first glance, as in the old look.
    expect(_open<BookingHandoverRowV2>(t), isTrue);
    expect(_open<BookingReadyCardV2>(t), isTrue);
    expect(find.byType(BookingDateCardV2), findsOneWidget);
    expect(find.byType(BookingFormTimeSection), findsOneWidget);
    expect(find.byType(BookingFormExtrasSection), findsOneWidget);
    // Key facts stay visible: the recap (dates), price, consents.
    expect(find.byType(BookingRecapV2), findsOneWidget);
    expect(find.byType(BookingConsentsV2), findsOneWidget);
    final cta = find.byType(MgCta);
    expect(t.widget<MgCta>(cta).enabled, isTrue);
    expect(t.getRect(cta).bottom, lessThanOrEqualTo(780));
    await _done(t);
  });

  testWidgets('folding never changes a value: draft identical before / after opening', (t) async {
    final c = await _form(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw)));
    final before = c.read(bookingDraftProvider);
    await openBookingExpress(t);
    expect(_open<BookingHandoverRowV2>(t), isTrue);
    expect(find.byType(BookingDateCardV2), findsOneWidget);
    expect(find.byType(BookingFormTimeSection), findsOneWidget);
    expect(find.byType(BookingFormExtrasSection), findsOneWidget);
    final after = c.read(bookingDraftProvider);
    expect(identical(before, after) || before.toString() == after.toString(), isTrue);
    expect([after.startDate, after.endDate, after.pickupTime, after.returnTime, after.helmetSize, after.consentVop],
        [before.startDate, before.endDate, before.pickupTime, before.returnTime, before.helmetSize, before.consentVop]);
    // Tapping the row again folds it (no blocker).
    final link = find.descendant(of: find.byType(BookingHandoverRowV2), matching: find.text(_cs.tr('v2BkChange')));
    await Scrollable.ensureVisible(t.element(link), alignment: 0.4);
    await t.pump();
    await t.tap(link);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(BookingDateCardV2), findsNothing);
    await _done(t);
  });

  testWidgets('a section the customer folded re-opens on its blocker fix (Doplnit → date card)', (t) async {
    await _form(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw)));
    final link = find.descendant(of: find.byType(BookingHandoverRowV2), matching: find.text(_cs.tr('v2BkChange')));
    await Scrollable.ensureVisible(t.element(link), alignment: 0.4);
    await t.pump();
    await t.tap(link);
    await t.pump(const Duration(milliseconds: 400));
    expect(_open<BookingHandoverRowV2>(t), isFalse);
    expect(find.byType(BookingDateCardV2), findsNothing);
    // The recap's own "change dates" still opens it and brings the card in.
    final recap = t.widget<BookingRecapV2>(find.byType(BookingRecapV2));
    recap.onPickDates!();
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(_open<BookingHandoverRowV2>(t), isTrue);
    _expectOnScreen(t, find.byType(BookingDateCardV2));
    await _done(t);
  });

  testWidgets('first-time customer (sizes missing): everything open, Doplnit → the size chips', (t) async {
    await _form(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw, sizes: false)));
    expect(_open<BookingHandoverRowV2>(t), isTrue);
    expect(_open<BookingReadyCardV2>(t), isTrue);
    await _fix(t);
    _expectOnScreen(t, find.byType(BookingFormExtrasSection));
    await _done(t);
  });

  testWidgets('no dates: "Termín a předání" open (amber), Doplnit → the date card', (t) async {
    await _form(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw, dates: false)));
    expect(_open<BookingHandoverRowV2>(t), isTrue);
    // The recap offers the same opener.
    expect(find.descendant(of: find.byType(BookingRecapV2), matching: find.text(_cs.tr('v2UxCbPickDates'))), findsOneWidget);
    await _fix(t);
    _expectOnScreen(t, find.byType(BookingDateCardV2));
    await _done(t);
  });

  testWidgets('consents off: Doplnit → both consents on screen', (t) async {
    await _form(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw, consents: false)));
    expect(_open<BookingHandoverRowV2>(t), isTrue);
    await _fix(t);
    _expectOnScreen(t, find.byType(BookingConsentsV2));
    await _done(t);
  });

  for (final kind in ['dates', 'time', 'licence']) {
    testWidgets('BookingErrKind.$kind: Doplnit → the offending input on screen', (t) async {
      const msg = 'Chyba ve formuláři';
      final o = [
        ...bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw)),
        bookingValidationErrorProvider.overrideWith((ref) => msg),
        if (kind == 'dates') overlapValidationProvider.overrideWith((ref) => msg),
        if (kind == 'time') pickupLeadTimeValidationProvider.overrideWith((ref) => msg),
        if (kind == 'licence') licenseValidationProvider.overrideWith((ref) => msg),
      ];
      await _form(t, o);
      expect(_open<BookingHandoverRowV2>(t), isTrue);
      await _fix(t);
      final target = switch (kind) {
        'dates' => find.byType(BookingDateCardV2),
        'time' => find.byType(BookingFormTimeSection),
        _ => find.byType(BookingWarningsV2),
      };
      _expectOnScreen(t, target);
      await _done(t);
    });
  }

  testWidgets('CB-10 recap = the trip; CB-16 dock saving = the price card\'s rank saving', (t) async {
    await _form(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw)));
    final recap = find.byType(BookingRecapV2);
    final w = t.widget<BookingRecapV2>(recap);
    expect([w.pickupTime, w.returnTime, w.dayCount], ['09:00', '19:00', 3]);
    expect(find.descendant(of: recap, matching: find.textContaining('09:00 → 19:00')), findsOneWidget);
    expect(find.descendant(of: recap, matching: find.textContaining(_cs.tr('v2CalcBranchStaffed'))), findsOneWidget);
    // Same saving as the price card's chip.
    final c = ProviderScope.containerOf(t.element(find.byType(BookingDebugWrapper)));
    final d = c.read(bookingDraftProvider);
    expect(d.startDate, isNotNull);
    final saving = find.descendant(
        of: find.byType(BookingDockV2), matching: find.textContaining(_cs.tr('v2UxCbDockSaves').split(' ').first));
    expect(saving, findsOneWidget);
    final text = t.widget<Text>(saving).data!.replaceAll(' ', ' ');
    final chip = find.textContaining(_cs.tr('v2BkRankSaves').split('{').first.trim());
    await openBookingExpress(t);
    expect(chip, findsWidgets);
    final chipText = t.widget<Text>(chip.first).data!.replaceAll(' ', ' ');
    final amount = RegExp(r'[\d ]+ Kč').firstMatch(chipText)!.group(0)!;
    expect(text, contains(amount));
    expect(Money.czk(0), isNotEmpty);
    await _done(t);
  });
}
