// Clarity "order" J8 / J10 / AFT-01 / AFT-03a / G-481 / G-535 / G-311 (new
// look, display only): the pay page names the rental dates; registration
// spells out the ID / licence labels and gives the country an example
// (value still empty); the pay strip's dismiss is a red "Zrušit" (it
// cancels the booking) and its confirm explains; the docs strip says the
// documents are REQUIRED; "required" on Moje doklady is a warning banner;
// a photo stored but not read is an amber note; the thank-you page points
// to the documents check when their state is unknown.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncValue;
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/core/shell_fabs.dart';
import 'package:motogo_app/core/shell_fabs_b.dart';
import 'package:motogo_app/core/v2/states/mg_state_banner.dart';
import 'package:motogo_app/core/v2/states/mg_tone.dart';
import 'package:motogo_app/features/auth/v2/auth_parts_v2.dart';
import 'package:motogo_app/features/auth/v2/register_view_v2.dart';
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/documents/docs_gate_provider.dart' show DocsScreenStatus;
import 'package:motogo_app/features/documents/v2/docs_view_v2.dart';
import 'package:motogo_app/features/documents/v2/scan_states_v2.dart';
import 'package:motogo_app/features/payment/card_minimum.dart';
import 'package:motogo_app/features/payment/v2/confirmation_view_v2.dart';
import 'package:motogo_app/features/payment/v2/pay_header_v2.dart';
import 'package:motogo_app/features/payment/v2/payment_view_v2.dart';

import '../render/cases_ux_auth_sos_misc.dart' show asmRegModel;
import '../render/cases_ux_pay_shop.dart' show kPsCards, psConfirm;
import '../support/fakes_booking.dart';
import '../support/fakes_docs_scan.dart';
import '../support/v2_harness.dart';

final _cs = AppTranslations.of('cs');
final _shot = GlobalKey();

DocsViewV2 _docs(DocsScreenStatus status) => DocsViewV2(
      verifiedAsync: AsyncValue.data(status),
      onBack: () {},
      onScan: () {},
      onScanMissing: () {},
      onScanId: () {},
      onScanDl: () {},
      onUpload: () {},
      onReset: (_) {},
      onRetry: () {},
    );

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerBookingStrings();
    mockBookingPathProvider();
  });

  for (final (lang, size) in [('cs', const Size(360, 780)), ('de', const Size(320, 690))]) {
    testWidgets('J8: new booking pay header names the dates ($lang ${size.width.toInt()})', (t) async {
      final draft = bookingDraft(kBmw)
        ..startDate = DateTime(2026, 12, 11)
        ..endDate = DateTime(2026, 12, 13);
      await pumpV2(
        t,
        PaymentViewV2(
          ctx: null,
          moto: kBmw,
          draft: draft,
          breakdown: const PriceBreakdown(
              basePrice: 10504, extrasTotal: 0, pickupDeliveryFee: 0, returnDeliveryFee: 0, discountTotal: 0, total: 10189, days: 3),
          extras: const [],
          bundledUpsell: const [],
          amount: 10189,
          charge: cardCharge(10189),
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
        ),
        lang: lang,
        size: size,
        scaffold: false,
        boundaryKey: _shot,
      );
      await t.pump(const Duration(milliseconds: 400));
      expect(t.takeException(), isNull);
      final sub = t.widget<PayHeaderV2>(find.byType(PayHeaderV2)).sub!.replaceAll('\u00A0', ' ').replaceAll('\u2060', '');
      expect(sub, contains(kBmw.model));
      if (lang == 'cs') {
        expect(sub, contains('11. 12.'));
        expect(sub, contains('13. 12. 2026'));
      }
      await maybeShot(t, _shot, 'clarity_order__pay_header__${lang}__${size.width.toInt()}x${size.height.toInt()}');
    });
  }

  testWidgets('J10: step 2 country hint (value empty), step 3 spelled-out labels', (t) async {
    final m2 = asmRegModel(2);
    await pumpV2(t, RegisterViewV2(m: m2), scaffold: false);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text(_cs.tr('coRegCountryHint')), findsOneWidget);
    expect(m2.ctrl['country']!.text, isEmpty);
    final m3 = asmRegModel(3);
    for (final (lang, size) in [('cs', const Size(360, 780)), ('de', const Size(320, 690))]) {
      await pumpV2(t, RegisterViewV2(m: m3), scaffold: false, lang: lang, size: size, boundaryKey: _shot);
      await t.pump(const Duration(milliseconds: 400));
      expect(t.takeException(), isNull);
      final tr = AppTranslations.of(lang);
      final labels = [for (final f in t.widgetList<AsmField>(find.byType(AsmField))) f.label];
      expect(labels, containsAll([tr.tr('coRegIdNumber'), tr.tr('coRegDlNumber')]));
      await maybeShot(t, _shot, 'clarity_order__register_s3__${lang}__${size.width.toInt()}x${size.height.toInt()}');
    }
  });

  testWidgets('AFT-01: pay strip dismiss = red "Zrušit", confirm explains; docs strip keeps ✕', (t) async {
    final pending = PendingBooking(id: 'b1', totalPrice: 12027, createdAt: DateTime.now());
    await pumpV2(t, Align(alignment: Alignment.topCenter, child: ShellBookingFab(booking: pending, v2: true)),
        boundaryKey: _shot);
    await t.pump(const Duration(milliseconds: 300));
    expect(t.takeException(), isNull);
    final cancel = find.text(_cs.tr('coStripCancel'));
    expect(cancel, findsOneWidget);
    await maybeShot(t, _shot, 'clarity_order__pay_strip__cs__360x780');
    await t.tap(cancel);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text(_cs.tr('cancelReservationQ')), findsOneWidget);
    expect(find.text(_cs.tr('coCancelPendingBody')), findsOneWidget);
    await t.tap(find.text(_cs.tr('back')));
    await t.pump(const Duration(milliseconds: 400));

    await pumpV2(t, ShellDocsFab(onTap: () {}, onDismiss: () {}, v2: true));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text(_cs.tr('coStripCancel')), findsNothing);
    expect(find.bySemanticsLabel(_cs.tr('close')), findsOneWidget);
    // AFT-03a: required, not "best before".
    expect(find.text(_cs.tr('coStripDocsNeeded')), findsOneWidget);
    expect(find.textContaining('Nejlépe'), findsNothing);
  });

  testWidgets('AFT-01: 320 px German pay strip fits', (t) async {
    final pending = PendingBooking(id: 'b1', totalPrice: 12027, createdAt: DateTime.now());
    await pumpV2(t, Align(alignment: Alignment.topCenter, child: ShellBookingFab(booking: pending, v2: true)),
        lang: 'de', size: const Size(320, 690), boundaryKey: _shot);
    await t.pump(const Duration(milliseconds: 300));
    expect(t.takeException(), isNull);
    await maybeShot(t, _shot, 'clarity_order__pay_strip__de__320x690');
  });

  testWidgets('G-481: incomplete docs → warn banner; complete → none', (t) async {
    await pumpV2(t, _docs(st(gate())), size: const Size(412, 3000), boundaryKey: _shot);
    await t.pump(const Duration(milliseconds: 50));
    final b = t.widget<MgStateBanner>(find.byKey(const ValueKey('docs-required-banner')));
    // R3-07: the dark card and the amber card no longer contradict.
    expect([b.tone, b.title, b.dark], [MgTone.warn, _cs.tr('efoDocsNeedBoth'), true]);
    expect(find.textContaining(_cs.tr('efoDocsNotVerified')), findsOneWidget);
    expect(find.textContaining('K rezervaci motorky potřebuješ'), findsNothing);
    expect(find.textContaining(_cs.tr('docsNotVerifiedDesc')), findsNothing);
    await maybeShot(t, _shot, 'clarity_order__docs_required__cs__412x3000');
    await pumpV2(t, _docs(st(gate(idF: true, idB: true, dlF: true, dlB: true), id: true, dl: true)), size: const Size(412, 3000));
    await t.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('docs-required-banner')), findsNothing);
  });

  testWidgets('G-535: photo saved but not read → amber note box', (t) async {
    await pumpV2(
        t,
        ScanResultV2(
            ok: true,
            side: 'ŘP – přední strana',
            message: _cs.tr('docPhotoSavedNoOcr'),
            guidance: '',
            remaining: 0,
            onContinue: () {},
            onRetry: () {},
            onSkip: () {}),
        size: const Size(412, 1200));
    await t.pump(const Duration(milliseconds: 400));
    final box = find.byKey(const ValueKey('scan-note-warn'));
    expect(box, findsOneWidget);
    expect(find.descendant(of: box, matching: find.text(_cs.tr('docPhotoSavedNoOcr'))), findsOneWidget);
  });

  testWidgets('G-311: unknown docs → "Zkontroluj doklady v profilu"; complete → absent', (t) async {
    await pumpV2(t, psConfirm(docs: PayDocsV2.unknown), scaffold: false);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text(_cs.tr('coPsDocsCheck')), findsOneWidget);
    await pumpV2(t, psConfirm(docs: PayDocsV2.verified), scaffold: false);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text(_cs.tr('coPsDocsCheck')), findsNothing);
  });
}
