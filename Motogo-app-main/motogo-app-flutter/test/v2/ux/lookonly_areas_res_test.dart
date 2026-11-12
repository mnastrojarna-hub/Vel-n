// lookonly-fix:areas (owner 2026-11-07 "jen upgrade vzhledu"): Rezervace
// list, detail and edit in the v2 look show the SAME blocks, actions,
// defaults and order as the original (flag OFF) screens.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/states/mg_support_row.dart';
import 'package:motogo_app/core/v2/widgets/mg_buttons.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/core/v2/widgets/mg_segmented.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_view_v2.dart';
import 'package:motogo_app/features/reservations/v2/reservations_screen_v2.dart';
import 'package:motogo_app/features/reservations/widgets/res_detail_tab_content.dart';
import 'package:motogo_app/features/reservations/widgets/res_payment_details_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/reservations_cases.dart';
import '../support/fakes_reservations.dart';
import '../support/v2_harness.dart';

String _cs(String key) => AppTranslations.of('cs').tr(key);

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerReservationStrings();
  });
  setUp(() {
    MgMotion.resetSession();
    SharedPreferences.setMockInitialValues({});
  });

  group('list', () {
    testWidgets('an empty filter shows the old empty block with REZERVOVAT; labels without counts', (t) async {
      final list = [resv('a1', status: 'reserved', from: 3, to: 5)];
      await pumpV2(t, const ReservationsScreenV2(),
          size: const Size(412, 1600), overrides: resOverrides(list: list, filter: 'cancelled'));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text(_cs('noReservations')), findsOneWidget);
      expect(find.text(_cs('noReservationsDesc')), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is MgCta && w.label == _cs('noResBookCta')), findsOneWidget);
      expect(find.text(_cs('v2ResShowAll')), findsNothing);
      // The old header: always visible back, no live pill.
      expect(find.byKey(const ValueKey('res-list-back')), findsOneWidget);
      expect(find.text(_cs('v2ResLive')), findsNothing);
      final seg = find.byWidgetPredicate((w) => w is MgSegmented && w.counts != null && w.counts!.isNotEmpty);
      expect(seg, findsNothing);
      await t.pump(const Duration(seconds: 2));
    });
  });

  group('edit', () {
    testWidgets('opens on the tab row + every section of "Prodloužit" at once, the CTA always docked', (t) async {
      final b = resv('d1', status: 'reserved', from: 5, to: 7);
      await pumpV2(t, editView(b), size: const Size(412, 4000));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey('res-edit-tabs')), findsOneWidget);
      // Calendar, pickup (place + time), return, moto, extras on ONE page.
      expect(find.text(_cs('pickupMotorcycle')), findsOneWidget);
      expect(find.text(_cs('returnMotorcycle')), findsOneWidget);
      expect(find.text('ČAS VYZVEDNUTÍ'), findsOneWidget);
      // Nothing changed → the save CTA is there, disabled (old button).
      final cta = t.widget<MgCta>(find.byWidgetPredicate((w) => w is MgCta && w.label == _cs('saveChangesBtn')));
      expect(cta.enabled, isFalse);
      await t.pump(const Duration(seconds: 2));
    });

    testWidgets('a tab tap calls the SAME tab closure; system back leaves the page (no chooser)', (t) async {
      final b = resv('d1', status: 'reserved', from: 5, to: 7);
      var shorten = 0;
      await pumpV2(t, editView(b, onShorten: () => shorten++), size: const Size(412, 4000));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.descendant(of: find.byType(ResEditV2View), matching: find.byType(PopScope)), findsNothing);
      await t.tap(find.descendant(of: find.byKey(const ValueKey('res-edit-tabs')), matching: find.text(_cs('v2ResIntShorten'))));
      await t.pump(const Duration(milliseconds: 400));
      expect(shorten, 1);
      await t.pump(const Duration(seconds: 2));
    });
  });

  group('detail', () {
    testWidgets('the old two tabs and the old blocks; no journey / CO TEĎ / support row', (t) async {
      final r = resv('u1', status: 'reserved', from: 3, to: 5);
      await pumpV2(t, detailView(r), size: const Size(412, 5000), overrides: resOverrides(list: [r]));
      await t.pump(const Duration(milliseconds: 800));
      expect(find.byKey(const ValueKey('res-detail-tabs')), findsOneWidget);
      expect(find.byType(ResDetailTabContent), findsOneWidget);
      expect(find.byType(MgSupportRow), findsNothing);
      // The old info rows incl. "Kategorie" and the old edit / cancel buttons.
      expect(find.text(_cs('resCategory')), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is MgCta && w.label == _cs('editReservation')), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is MgBtnDestructive && w.label == _cs('cancelReservationBtn')), findsOneWidget);
      // Second tab = the old payment details.
      await t.tap(find.text(_cs('paymentDetailsTab')));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(ResPaymentDetailsTab), findsOneWidget);
      expect(find.byType(ResDetailTabContent), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
    });
  });
}
