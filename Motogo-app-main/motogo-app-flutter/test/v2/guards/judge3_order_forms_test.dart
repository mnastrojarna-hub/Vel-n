// Judge-3 fixes, partition "order" (forms and documents), new look only:
// R3-04 a picked date clears its stale error (register dob / licence
// expiry); R3-05 the phone error names the full number; R3-06 an empty
// "Doplnit" opens the same personal form as "Upravit"; R3-07 the documents
// texts no longer contradict each other; R3-13 the GDPR badge is
// localized; E3-08 an edit surcharge says the change applies once paid.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/icons/mg_icon.dart';
import 'package:motogo_app/features/auth/register_screen.dart';
import 'package:motogo_app/features/auth/v2/date_field_v2.dart';
import 'package:motogo_app/features/auth/v2/register_view_v2.dart';
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/documents/v2/scan_choice_v2.dart';
import 'package:motogo_app/features/payment/card_minimum.dart';
import 'package:motogo_app/features/payment/payment_provider.dart';
import 'package:motogo_app/features/payment/v2/payment_view_v2.dart';
import 'package:motogo_app/features/profile/v2/profile_personal_form_v2.dart';

import '../render/cases_ux_auth_sos_misc.dart' show asmRegModel;
import '../render/cases_ux_pay_shop.dart' show kPsCards;
import '../support/asm_harness.dart';
import '../support/fakes_booking.dart';
import '../support/fakes_profile.dart';
import '../support/profile_harness.dart';
import '../support/v2_harness.dart';

final _cs = AppTranslations.of('cs');
String _c(String k) => _cs.tr(k);

/// Picks 15 / 6 / [year] through the v2 date row's own callbacks (the same
/// setState + write the day / month / year sheets do).
Future<void> _pickDate(WidgetTester t, Finder row, int year) async {
  final r = t.widget<DateFieldRowV2>(row);
  r.onDay(15);
  await t.pump();
  t.widget<DateFieldRowV2>(row).onMonth(6);
  await t.pump();
  t.widget<DateFieldRowV2>(row).onYear(year);
  await t.pump();
}

PaymentViewV2 _pay(PaymentContext? ctx) => PaymentViewV2(
      ctx: ctx,
      moto: ctx == null ? kBmw : null,
      draft: bookingDraft(kBmw),
      breakdown: const PriceBreakdown(
          basePrice: 10504, extrasTotal: 0, pickupDeliveryFee: 0, returnDeliveryFee: 0, discountTotal: 0, total: 10189, days: 3),
      extras: const [],
      bundledUpsell: const [],
      amount: 7469,
      charge: cardCharge(7469),
      serverAmount: null,
      forceMin: false,
      defaultCard: kPsCards.first,
      processing: false,
      expired: false,
      verifying: false,
      timeRemaining: '29:59',
      lastMinutes: false,
      upsellProducts: false,
      onBack: () {},
      onPay: () {},
    );

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerBookingStrings();
    mockBookingPathProvider();
  });

  testWidgets('R3-05 + R3-04: register step 1 — full-number phone error, a picked birth date clears its error', (t) async {
    await pumpAsmRouted(t, const RegisterScreen(initialEmail: 'jan@x.cz'));
    await t.pump();
    final fields = find.byType(TextField);
    await t.enterText(fields.at(0), 'Jan');
    await t.enterText(fields.at(1), 'Novák');
    await t.enterText(fields.at(3), '+420 777');
    await t.pump();
    await t.tap(find.text('POKRAČOVAT'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text(_c('efoPhoneErr')), findsOneWidget);
    expect(_c('efoPhoneErr').replaceAll('\u00A0', ' '), contains('+420 777 123 456'));
    expect(find.text(_c('v2UxAsmErrPhone')), findsNothing);

    await t.enterText(fields.at(3), '+420 777 123 456');
    await t.pump();
    await t.tap(find.text('POKRAČOVAT'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text(_c('v2UxAsmErrDob')), findsOneWidget);
    await _pickDate(t, find.byType(DateFieldRowV2).first, DateTime.now().year - 50);
    expect(find.text(_c('v2UxAsmErrDob')), findsNothing, reason: 'a full date clears the stale error');
  });

  for (final (step, field, year) in [(1, 'dob', DateTime.now().year - 50), (3, 'licExp', DateTime.now().year + 2)]) {
    testWidgets('R3-04: step $step — the first full date fires onEdited($field)', (t) async {
      final edited = <String>[];
      final base = asmRegModel(step, errors: {field: 'CHYBA'});
      final m = RegisterV2Model(
        step: step, loading: false, forward: true, ctrl: base.ctrl, licGroup: 'A2', onLic: (_) {},
        consentVop: false, consentGdpr: false, onVop: (_) {}, onGdpr: (_) {}, errors: {field: 'CHYBA'},
        keyFor: base.keyFor, onEdited: edited.add, onBack: () {}, onNext: () {},
      );
      await pumpV2(t, RegisterViewV2(m: m), scaffold: false, size: const Size(360, 2000));
      await t.pump();
      expect(find.text('CHYBA'), findsOneWidget);
      await _pickDate(t, find.byType(DateFieldRowV2).first, year);
      expect(edited, contains(field));
    });
  }

  testWidgets('R3-06: an empty "Doplnit" (Telefon) opens the same form as "Upravit"', (t) async {
    final noPhone = {...kProfileFull, 'phone': ''};
    await pumpV2(t, const PfHubHarness(),
        overrides: profileOverrides(profile: noPhone), size: const Size(412, 4000), reducedMotion: true);
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(ProfilePersonalFormV2), findsNothing);
    final fill = find.byKey(ValueKey('pf-fill-${_c('phone')}'));
    expect(fill, findsOneWidget);
    expect(t.getSize(fill).height, greaterThanOrEqualTo(44));
    await t.ensureVisible(fill);
    await t.tap(fill);
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(ProfilePersonalFormV2), findsOneWidget);
    // A filled value is not a button (only empty ones say "Doplnit").
    expect(find.byKey(ValueKey('pf-fill-${_c('fullNameLabel')}')), findsNothing);
  });

  testWidgets('R3-13: scan choice badge is localized', (t) async {
    for (final lang in ['cs', 'de']) {
      await pumpV2(
          t,
          ScanChoiceV2(onBack: () {}, note: 'x', choices: [
            (icon: MgIcons.idCard, label: 'OP', steps: 4, sub: 's', onTap: () {}),
          ]),
          scaffold: false,
          lang: lang,
          size: const Size(320, 690));
      await t.pump();
      expect(find.text(AppTranslations.of(lang).tr('efoGdprBadge')), findsOneWidget);
      expect(find.text('EU GDPR compliant'), findsNothing);
      expect(t.takeException(), isNull);
    }
    expect(_c('efoGdprBadge'), 'Podle GDPR (EU)');
  });

  testWidgets('E3-08: edit surcharge says the change applies once paid; a new booking does not', (t) async {
    final ctx = PaymentContext(
        flowType: PaymentFlowType.extension, bookingId: 'aaaa-bbbb-8f3a2c1d', amount: 7469, label: _c('extensionSurcharge'));
    await pumpV2(t, _pay(ctx), scaffold: false, size: const Size(320, 690));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text(_c('efoSurchargeAfterPay')), findsOneWidget);
    expect(t.takeException(), isNull);
    await pumpV2(t, _pay(null), scaffold: false);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text(_c('efoSurchargeAfterPay')), findsNothing);
  });
}
