// Clarity "order" J1 / J2 / G-179..G-182 / J6 / J7 (new look): the locked
// booking form says WHY in the dock (licence / dates / time instead of the
// general "Zkontroluj termín a údaje výše") and "Ukázat proč" scrolls to
// the place that explains / fixes it; the licence card has ONE primary fix
// and no duplicate "Doplnit v profilu"; the date card labels the list price
// and says that struck-through days are taken. canProceed is untouched.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/booking_form_time_section.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/states/mg_state_banner.dart';
import 'package:motogo_app/core/v2/widgets/mg_buttons.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/booking/v2/booking_date_v2.dart';
import 'package:motogo_app/features/booking/v2/booking_dock_v2.dart';
import 'package:motogo_app/features/booking/v2/booking_form_view_v2.dart';
import 'package:motogo_app/features/booking/v2/booking_sync_v2.dart' show BookingErrKind;
import 'package:motogo_app/features/booking/v2/booking_warning_v2.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes_booking.dart';
import 'support/v2_harness.dart';

String _tr(String key) => translations['cs']![key]!;
final _shot = GlobalKey();

const _bd = PriceBreakdown(
    basePrice: 12261, extrasTotal: 0, pickupDeliveryFee: 0, returnDeliveryFee: 0, discountTotal: 368, total: 11893, days: 3);

Future<void> _view(
  WidgetTester t, {
  String? err,
  BookingErrKind? errKind,
  String? profileErr,
  bool dates = true,
  Size size = const Size(412, 915),
}) async {
  final draft = bookingDraft(kBmw, dates: dates);
  await pumpV2(
    t,
    BookingFormV2View(
      moto: kBmw,
      draft: draft,
      bd: _bd,
      pricedExtras: const [],
      err: err,
      profileErr: profileErr,
      hasDates: dates,
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
      errKind: errKind,
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
    size: size,
    overrides: bookingOverrides(moto: kBmw, draft: draft),
    boundaryKey: _shot,
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

Finder _showWhy() => find.byWidgetPredicate((w) => w is Semantics && w.properties.label == _tr('v2BkShowWhy'));

Future<void> _tapShowWhy(WidgetTester t) async {
  final f = find.descendant(of: find.byType(BookingDockV2), matching: _showWhy());
  expect(f, findsOneWidget, reason: '"Ukázat proč" next to the blocker');
  await t.tap(f);
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _done(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 2));
}

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
  const licErr = 'Vaše řidičské oprávnění (B) nestačí na tuto motorku (vyžaduje A).';

  testWidgets('J1: licence → "Chybí vhodný řidičák" + "Ukázat proč" shows the reason', (t) async {
    await _view(t, err: licErr, errKind: BookingErrKind.licence);
    final dock = t.widget<BookingDockV2>(find.byType(BookingDockV2));
    expect(dock.blocker, _tr('v2BkBlockLicence'));
    expect(find.text(_tr('v2BkBlockLicence')), findsOneWidget);
    expect(find.text(_tr('v2BkBlockError')), findsNothing);
    expect(t.widget<MgCta>(find.byType(MgCta).last).enabled, isFalse, reason: 'lock unchanged');
    expect(find.text(_tr('v2BkErrTitle')).hitTestable(), findsNothing, reason: 'reason is far below at first');
    await _tapShowWhy(t);
    expect(find.text(_tr('v2BkErrTitle')).hitTestable(), findsOneWidget, reason: 'the red card is in view');
    await maybeShot(t, _shot, 'clarity_order__booking_blocker_licence__cs__412x915');
    await _done(t);
  });

  for (final size in const [Size(360, 780), Size(320, 690)]) {
    testWidgets('J1: blocked dock fits at ${size.width.toInt()} (shot)', (t) async {
      await _view(t, err: licErr, errKind: BookingErrKind.licence, size: size);
      expect(t.takeException(), isNull);
      expect(find.descendant(of: find.byType(BookingDockV2), matching: _showWhy()), findsOneWidget);
      await maybeShot(t, _shot, 'clarity_order__booking_dock_licence__cs__${size.width.toInt()}x${size.height.toInt()}');
      await _done(t);
    });
  }

  testWidgets('J1 / G-180..G-182: time → "Změň čas vyzvednutí", link scrolls to the time section', (t) async {
    await _view(t, err: 'Vyzvednutí musí být nejdříve za 1 hodinu.', errKind: BookingErrKind.time);
    expect(find.text(_tr('v2BkBlockTime')), findsOneWidget);
    // Scroll away first so the scroll back is what brings it into view.
    await t.drag(find.byType(Scrollable).first, const Offset(0, -2400));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(BookingFormTimeSection).hitTestable(), findsNothing);
    await _tapShowWhy(t);
    expect(find.byType(BookingFormTimeSection).hitTestable(), findsOneWidget);
    await _done(t);
  });

  testWidgets('J1: dates kind → "Termín nejde – změň ho"', (t) async {
    await _view(t, err: 'Minimální délka pronájmu je 2 dny.', errKind: BookingErrKind.dates);
    expect(find.text(_tr('v2BkBlockDatesBad')), findsOneWidget);
    await _done(t);
  });

  testWidgets('G-179: no dates → "Vyber termín" + link to the date card', (t) async {
    await _view(t, dates: false);
    expect(find.text(_tr('v2BkBlockDates')), findsOneWidget);
    await t.drag(find.byType(Scrollable).first, const Offset(0, -2400));
    await t.pump(const Duration(milliseconds: 400));
    await _tapShowWhy(t);
    expect(find.byType(BookingDateCardV2).hitTestable(), findsOneWidget);
    await _done(t);
  });

  testWidgets('J2: licence + incomplete profile → ONE "Doplnit v profilu", other bike stays', (t) async {
    await _view(t, err: licErr, errKind: BookingErrKind.licence, profileErr: 'Doplň adresu v profilu.');
    expect(find.text(_tr('completeProfileBtn')), findsOneWidget);
    expect(find.text(_tr('pdPickOtherMoto')), findsOneWidget);
    await _done(t);
  });

  testWidgets('J2: licence alone → "Doplnit v profilu" is the first, ink button', (t) async {
    await _view(t, err: licErr, errKind: BookingErrKind.licence);
    final card = find.ancestor(of: find.text(_tr('v2BkErrTitle')), matching: find.byType(MgStateBanner));
    final banner = t.widget<MgStateBanner>(card);
    expect(banner.actions.first, isA<MgBtnInk>());
    expect((banner.actions.first as MgBtnInk).label, _tr('completeProfileBtn'));
    expect(banner.actions.last, isA<MgBtnGhostLight>());
    expect((banner.actions.last as MgBtnGhostLight).label, _tr('pdPickOtherMoto'));
    expect(find.byType(BookingWarningsV2), findsOneWidget);
    await t.ensureVisible(card);
    await t.pump(const Duration(milliseconds: 300));
    await maybeShot(t, _shot, 'clarity_order__booking_licence_card__cs__412x915');
    await _done(t);
  });

  testWidgets('J6 / J7: list price label + taken-days hint in the open calendar', (t) async {
    final (s, e) = futureWeekend();
    await pumpV2(
      t,
      SingleChildScrollView(
        child: BookingDateCardV2(
          start: s,
          end: e,
          hasDates: true,
          dayCount: 3,
          basePrice: 12261,
          calOpen: true,
          booked: const AsyncValue.data(<BookedDateRange>[]),
          onOpenCalendar: () {},
          onRangeSelected: (_, __) {},
          onReset: () {},
          onRetryBooked: () {},
        ),
      ),
      boundaryKey: _shot,
    );
    await t.pump(const Duration(milliseconds: 400));
    expect(t.takeException(), isNull);
    expect(find.text(_tr('v2BkListPrice')), findsOneWidget);
    expect(find.text(_tr('totalForRental')), findsNothing);
    expect(find.textContaining('12'), findsWidgets);
    expect(find.text(_tr('v2BkCalTakenHint')), findsOneWidget);
    await maybeShot(t, _shot, 'clarity_order__date_card__cs__360x780');
  });
}
