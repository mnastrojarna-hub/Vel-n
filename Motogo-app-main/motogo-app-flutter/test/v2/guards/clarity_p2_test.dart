// Second confused-customer walk (new look, P2-01..P2-04), display only:
// the pickup-time error is shown under the time card where "Ukázat proč"
// lands; with no licence AND an incomplete profile the red card's first
// button is "Doplnit v profilu" (once on the page); the bike detail dock
// with a start day only says "1 den" and how to make it longer; the unpaid
// booking strip says "Zaplatit rezervaci" + the amount, and the detail's
// status pill is amber. Validators, targets and the lock are untouched.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/currency.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/core/shell_fabs.dart';
import 'package:motogo_app/core/v2/chrome/mg_status_strip.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/states/mg_state_banner.dart';
import 'package:motogo_app/core/v2/widgets/mg_buttons.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/booking/v2/booking_form_view_v2.dart';
import 'package:motogo_app/features/booking/v2/booking_sync_v2.dart' show BookingErrKind;
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_dock_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_detail_parts_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_booking.dart';
import '../support/fakes_reservations.dart';
import '../support/v2_harness.dart';

String _tr(String key) => translations['cs']![key]!;
final _shot = GlobalKey();

const _bd = PriceBreakdown(
    basePrice: 12261, extrasTotal: 0, pickupDeliveryFee: 0, returnDeliveryFee: 0, discountTotal: 368, total: 11893, days: 3);

Future<void> _form(WidgetTester t, {String? err, BookingErrKind? errKind, String? profileErr}) async {
  final draft = bookingDraft(kBmw, dates: true);
  await pumpV2(
    t,
    BookingFormV2View(
      moto: kBmw,
      draft: draft,
      bd: _bd,
      pricedExtras: const [],
      err: err,
      profileErr: profileErr,
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

  testWidgets('P2-01: time error is shown under the pickup-time card, lock unchanged', (t) async {
    const err = 'Na obslužné pobočce je vyzvednutí možné nejdříve za 1 hodinu od teď. Vyberte pozdější čas.';
    await _form(t, err: err, errKind: BookingErrKind.time);
    final near = find.byKey(const ValueKey('bk-time-err'));
    expect(near, findsOneWidget);
    expect(find.descendant(of: near, matching: find.text(err)), findsOneWidget);
    expect(find.text(err), findsNWidgets(2), reason: 'the bottom red card stays');
    expect(t.widget<MgCta>(find.byType(MgCta).last).enabled, isFalse);
    await t.ensureVisible(near);
    await t.pump(const Duration(milliseconds: 300));
    await maybeShot(t, _shot, 'clarity_p2__booking_time_err__cs__360x780');
    await _done(t);
  });

  testWidgets('P2-01: other errors draw nothing under the time card', (t) async {
    await _form(t, err: 'x', errKind: BookingErrKind.licence);
    expect(find.byKey(const ValueKey('bk-time-err')), findsNothing);
    await _done(t);
  });

  testWidgets('P2-03: licence + profile → red card leads with "Doplnit v profilu", once on the page', (t) async {
    await _form(t, err: 'Nemáte v profilu žádný řidičský průkaz.', errKind: BookingErrKind.licence, profileErr: 'Doplň adresu.');
    final red = t.widget<MgStateBanner>(find.ancestor(of: find.text(_tr('v2BkErrTitle')), matching: find.byType(MgStateBanner)));
    expect((red.actions.first as MgBtnInk).label, _tr('completeProfileBtn'));
    expect((red.actions.last as MgBtnGhostLight).label, _tr('pdPickOtherMoto'));
    final amber = t.widget<MgStateBanner>(find.ancestor(of: find.text(_tr('v2BkProfileTitle')), matching: find.byType(MgStateBanner)));
    expect(amber.actions, isEmpty);
    expect(find.text(_tr('completeProfileBtn')), findsOneWidget);
    await t.ensureVisible(find.text(_tr('v2BkProfileTitle')));
    await t.pump(const Duration(milliseconds: 300));
    await maybeShot(t, _shot, 'clarity_p2__booking_licence_profile__cs__360x780');
    await _done(t);
  });

  testWidgets('P2-03: profile alone keeps its own "Doplnit v profilu"', (t) async {
    await _form(t, profileErr: 'Doplň adresu.');
    final amber = t.widget<MgStateBanner>(find.ancestor(of: find.text(_tr('v2BkProfileTitle')), matching: find.byType(MgStateBanner)));
    expect(amber.actions, hasLength(1));
    await _done(t);
  });

  testWidgets('P2-02: start day only → "1 den" + return-day hint, REZERVOVAT unchanged', (t) async {
    var taps = 0;
    await pumpV2(
      t,
      Align(
        alignment: Alignment.bottomCenter,
        child: DetailDockV2(selStart: DateTime(2026, 12, 3), selEnd: null, dayCount: 1, price: null, onReserve: () => taps++),
      ),
      boundaryKey: _shot,
    );
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('detail-dock-one-day')), findsOneWidget);
    expect(find.textContaining('1 den'), findsOneWidget);
    expect(find.text(_tr('coDetDockOneDay')), findsOneWidget);
    await t.tap(find.byType(MgCta));
    expect(taps, 1);
    await maybeShot(t, _shot, 'clarity_p2__detail_dock_one_day__cs__360x780');
    await _done(t);
  });

  testWidgets('P2-02: a full range keeps the plain line', (t) async {
    await pumpV2(
      t,
      Align(
        alignment: Alignment.bottomCenter,
        child: DetailDockV2(
            selStart: DateTime(2026, 12, 3), selEnd: DateTime(2026, 12, 5), dayCount: 3, price: '8 000 Kč', onReserve: () {}),
      ),
    );
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('detail-dock-one-day')), findsNothing);
    expect(find.text(_tr('coDetDockOneDay')), findsNothing);
    await _done(t);
  });

  testWidgets('P2-04: unpaid strip says "Zaplatit rezervaci" + amount + time', (t) async {
    final p = PendingBooking(id: 'b1', totalPrice: 11893, createdAt: DateTime.now());
    await pumpV2(t, Align(alignment: Alignment.bottomCenter, child: ShellBookingFab(booking: p, v2: true)), boundaryKey: _shot);
    await t.pump(const Duration(milliseconds: 300));
    final strip = t.widget<MgStatusStrip>(find.byType(MgStatusStrip));
    expect(strip.title, _tr('coPayNowFab'));
    expect(strip.sub, contains(Money.czk(11893)));
    expect(strip.sub, contains(p.timeLabel));
    expect(strip.dismissDestructive, isTrue);
    await maybeShot(t, _shot, 'clarity_p2__pay_strip__cs__360x780');
    await _done(t);
  });

  testWidgets('P2-04: unpaid booking → amber status pill in the detail card', (t) async {
    final r = resv('u1', status: 'pending', pay: 'unpaid', from: 9, to: 11);
    await pumpV2(
      t,
      ResDetailHeadV2(res: r),
      overrides: [
        pendingBookingFabProvider.overrideWith((ref) => Stream.value(PendingBooking(id: r.id, totalPrice: 1, createdAt: DateTime.now()))),
      ],
    );
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('res-status-pill-warn')), findsOneWidget);
    await _done(t);
  });

  testWidgets('P2-04: paid booking → normal status pill', (t) async {
    final r = resv('u2', status: 'upcoming', from: 9, to: 11);
    await pumpV2(
      t,
      ResDetailHeadV2(res: r),
      overrides: [pendingBookingFabProvider.overrideWith((ref) => Stream.value(null))],
    );
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('res-status-pill-warn')), findsNothing);
    await _done(t);
  });
}
