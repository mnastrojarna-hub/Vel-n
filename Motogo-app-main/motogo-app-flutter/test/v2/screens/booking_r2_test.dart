// fix:booking:r2 — the booking form (v2): a carried range with a booked day
// opens the calendar and locks the CTA (own unpaid draft excepted), "Ponechat
// termín" folds the calendar without re-picking, the error banner offers the
// fix, sized extras announce "selected" (no toggle), the passenger sheet
// speaks the app language, a voucher chip only fills the code.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/booking_form_widget.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/booking/booking_provider.dart';
import 'package:motogo_app/features/booking/my_vouchers.dart';
import 'package:motogo_app/features/booking/v2/booking_sync_v2.dart';
import 'package:motogo_app/features/booking/v2/sections/extras_rows_v2.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/catalog/widgets/availability_calendar.dart';
import 'package:motogo_app/features/reservations/reservation_models.dart';
import 'package:motogo_app/features/reservations/reservation_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_booking.dart';
import '../support/v2_harness.dart';

String _tr(String key, [String lang = 'cs']) => translations[lang]![key]!;

Future<ProviderContainer> _form(WidgetTester t, List<Override> o, {String lang = 'cs'}) async {
  await pumpV2(t, const BookingDebugWrapper(), lang: lang, size: const Size(412, 915), overrides: o);
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
  return ProviderScope.containerOf(t.element(find.byType(BookingDebugWrapper)));
}

Future<void> _done(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 2));
}

Future<void> _tap(WidgetTester t, Finder f) async {
  // Mid-viewport: at the top edge it would sit under the pinned back bar.
  await Scrollable.ensureVisible(t.element(f), alignment: 0.4);
  await t.pump();
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 500));
}

MgCta _cta(WidgetTester t) => t.widget<MgCta>(find.byType(MgCta).last);

Reservation _ownDraft(DateTime s, DateTime e) => Reservation.fromJson({
      'id': 'own-1',
      'moto_id': 'm-bmw',
      'status': 'pending',
      'payment_status': 'unpaid',
      'booking_source': 'app',
      'start_date': s.toIso8601String(),
      'end_date': e.toIso8601String(),
      'total_price': 0,
    });

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
  final (s, e) = futureWeekend();

  test('busy rule: a booked day inside the range; own unpaid draft and unknown data do not block', () {
    final day = [BookedDateRange(start: e, end: e, status: 'reserved')];
    expect(bookingRangeBusy(booked: day, own: const [], motoId: 'm-bmw', start: s, end: e), isTrue);
    expect(bookingRangeBusy(booked: day, own: const [], motoId: 'm-bmw', start: s, end: s), isFalse);
    expect(bookingRangeBusy(booked: null, own: const [], motoId: 'm-bmw', start: s, end: e), isFalse);
    expect(bookingRangeBusy(booked: day, own: null, motoId: 'm-bmw', start: s, end: e), isFalse);
    final mine = [BookedDateRange(start: s, end: e, status: 'pending')];
    expect(bookingRangeBusy(booked: mine, own: [_ownDraft(s, e)], motoId: 'm-bmw', start: s, end: e), isFalse);
    expect(bookingRangeBusy(booked: mine, own: [_ownDraft(s, e)], motoId: 'm-husq', start: s, end: e), isTrue);
  });

  testWidgets('carried range with a booked day: calendar open with the reason, CTA locked', (t) async {
    await _form(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw),
        booked: [BookedDateRange(start: e, end: e, status: 'reserved')]));
    expect(find.byType(AvailabilityCalendar), findsOneWidget);
    expect(find.text(_tr('v2CalcRangeBusy')), findsOneWidget);
    expect(find.text(_tr('v2BkKeepDates')), findsNothing);
    expect(find.text(_tr('v2BkBlockBusy')), findsOneWidget);
    expect(_cta(t).enabled, isFalse);
    await _done(t);
  });

  testWidgets('own unpaid draft of the same dates does not lock the form', (t) async {
    await _form(t, [
      ...bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw),
          booked: [BookedDateRange(start: s, end: e, status: 'pending')]),
      reservationsProvider.overrideWith((ref) => Stream.value([_ownDraft(s, e)])),
    ]);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(AvailabilityCalendar), findsNothing);
    expect(find.text(_tr('v2CalcRangeBusy')), findsNothing);
    expect(_cta(t).enabled, isTrue);
    await _done(t);
  });

  testWidgets('"Změnit" → "Ponechat termín" folds the calendar, dates unchanged', (t) async {
    final c = await _form(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw)));
    expect(find.byType(AvailabilityCalendar), findsNothing);
    await _tap(t, find.text(_tr('v2BkChange')).first);
    expect(find.byType(AvailabilityCalendar), findsOneWidget);
    await _tap(t, find.text(_tr('v2BkKeepDates')));
    expect(find.byType(AvailabilityCalendar), findsNothing);
    final d = c.read(bookingDraftProvider);
    expect([d.startDate, d.endDate], [s, e]);
    await _done(t);
  });

  testWidgets('licence error: banner offers another bike and the profile', (t) async {
    await _form(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw), profile: {...kProfileOk, 'license_group': ['B']}));
    expect(find.text(_tr('v2BkErrTitle')), findsOneWidget);
    expect(find.text(_tr('pdPickOtherMoto')), findsOneWidget);
    expect(find.text(_tr('completeProfileBtn')), findsOneWidget);
    expect(_cta(t).enabled, isFalse);
    await _done(t);
  });

  testWidgets('chosen boots: "selected" + change/remove hint, not a checkbox', (t) async {
    final sem = t.ensureSemantics();
    final boots = SelectedExtra(id: 'extra-boty-ridic', name: 'Boty řidiče', price: 0, size: '43');
    await _form(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw, extras: [boots])));
    final row = find.byWidgetPredicate((w) => w is BookingExtraRowV2 && w.selected && w.opensSheet);
    expect(row, findsOneWidget);
    await t.ensureVisible(row);
    await t.pump(const Duration(milliseconds: 300));
    final node = t.getSemantics(find.bySemanticsLabel(RegExp('^${RegExp.escape(_tr('driverBootsLabel'))}, ')));
    expect(node, isSemantics(isSelected: true, hasCheckedState: false, isButton: true));
    expect(node.getSemanticsData().hint, contains(_tr('removeBtn')));
    sem.dispose();
    await _done(t);
  });

  testWidgets('passenger sheet in English: English labels and title, Czech keys stored', (t) async {
    final c = await _form(t, bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw)), lang: 'en');
    await _tap(t, find.text(_tr('passengerGearLabel', 'en')).first);
    expect(find.text('${_tr('sizesLabel', 'en')} – ${_tr('passengerGearLabel', 'en')}'), findsOneWidget);
    for (final k in ['helmet', 'gloves', 'jacket', 'pants']) {
      expect(find.text(_tr(k, 'en')), findsWidgets);
    }
    expect(find.text('Rukavice'), findsNothing);
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
    await _tap(t, find.descendant(of: find.byType(BottomSheet), matching: find.text('L')).first);
    await _tap(t, find.text(_tr('confirm', 'en').toUpperCase()));
    final x = c.read(bookingDraftProvider).extras.firstWhere((x) => x.id == 'extra-spolujezdec');
    expect(x.size, 'Helma: L');
    expect(extraSizeLabel((k) => _tr(k, 'en'), x.size!), '${_tr('helmet', 'en')}: L');
    await _done(t);
  });

  testWidgets('voucher chip fills the code; nothing is applied until "Použít"', (t) async {
    final c = await _form(t, [
      ...bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw)),
      myVouchersProvider.overrideWith((ref) async => const [MyVoucher(code: 'DAREK500', amount: 500)]),
    ]);
    await t.pump(const Duration(milliseconds: 300));
    await _tap(t, find.textContaining('DAREK500').first);
    final field = t.widget<TextField>(find.byType(TextField).last);
    expect(field.controller!.text, 'DAREK500');
    expect(c.read(bookingDraftProvider).discounts, isEmpty);
    await t.tap(find.text(_tr('cancel')));
    await t.pump(const Duration(milliseconds: 400));
    expect(c.read(bookingDraftProvider).discounts, isEmpty);
    await _done(t);
  });
}
