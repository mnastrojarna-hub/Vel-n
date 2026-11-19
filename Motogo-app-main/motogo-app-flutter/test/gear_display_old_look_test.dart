// 5.0.2 výpůjčka JEN výbavy ve STARÉM vzhledu (kill-switch app_v2_ui=false):
// karta seznamu, karta Domů, detail (kód šatny, kroky, bez SOS / hodnocení)
// a úprava (velikosti, termín na webu, storno) — stejné údaje jako v2.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/home/widgets/home_reservation_card.dart';
import 'package:motogo_app/features/reservations/gear/gear_edit_view.dart';
import 'package:motogo_app/features/reservations/gear/gear_edit_screen.dart';
import 'package:motogo_app/features/reservations/widgets/res_rating_card.dart';
import 'package:motogo_app/features/reservations/widgets/reservation_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'v2/screens/gear_display_test.dart' show gearRes, gearOverrides, detail;
import 'v2/support/fakes_reservations.dart';
import 'v2/support/v2_harness.dart';

String _cs(String k) => AppTranslations.of('cs').tr(k);

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerReservationStrings();
  });
  setUp(() {
    MgMotion.resetSession();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('starý vzhled: karta seznamu a Domů — výbava, souhrn, ikona místo fotky', (t) async {
    final r = gearRes();
    await pumpV2(t, ListView(children: [
      ReservationCard(reservation: r, onTap: () {}, onEdit: () {}),
      HomeReservationCard(reservation: r),
    ]), v2: false, overrides: gearOverrides([r]));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Výpůjčka výbavy'), findsNWidgets(2));
    expect(find.textContaining('Komplet bez bot (M, L, L, M) · Boty 43'), findsOneWidget);
    expect(find.byIcon(Icons.checkroom), findsNWidgets(2));
    expect(find.byIcon(Icons.motorcycle), findsNothing);

    final done = gearRes(status: 'completed', from: -4, to: -3);
    await pumpV2(t, ReservationCard(reservation: done, onTap: () {}), v2: false, overrides: gearOverrides([done]));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining(_cs('rateBtn')), findsNothing);
    final gone = gearRes(status: 'cancelled');
    await pumpV2(t, ReservationCard(reservation: gone, onTap: () {}, onRestore: () {}), v2: false, overrides: gearOverrides([gone]));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining(_cs('restoreBtn')), findsNothing);
  });

  testWidgets('starý vzhled: detail — kód šatny + protokol, kroky výbavy, bez SOS a hodnocení', (t) async {
    final r = gearRes(status: 'reserved', from: 0, to: 1);
    await pumpV2(t, detail(r, codes: [code('accessories', '4321')]),
        size: const Size(412, 4000), v2: false, overrides: gearOverrides([r]));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('4321'), findsOneWidget);
    expect(find.textContaining(_cs('gearProtocolFirst')), findsOneWidget);
    expect(find.text(_cs('motoCode')), findsNothing);
    expect(find.text('Výpůjčka výbavy'), findsOneWidget);
    expect(find.byType(ResRatingCard), findsNothing);
    expect(find.textContaining(_cs('sosTitle')), findsNothing);
    expect(find.text(_cs('resCategory')), findsNothing);
    // Postup na pobočce (rozbalovací, starý vzhled) obsahuje kroky výbavy.
    await t.tap(find.text(_cs('pickupProcedure')));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text(_cs('gearProcStep2')), findsOneWidget);
    expect(find.text(_cs('gearProcReturn')), findsOneWidget);
    expect(find.text(_cs('procStep2NoGear')), findsNothing);
  });

  testWidgets('starý vzhled: obslužná pobočka — předání obsluhou, bez kroků kiosku', (t) async {
    final r = gearRes(self: false);
    await pumpV2(t, detail(r), size: const Size(412, 4000), v2: false, overrides: gearOverrides([r]));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text(_cs('gearStaffedPickup')), findsOneWidget);
    expect(find.text(_cs('pickupProcedure')), findsNothing);
    expect(find.text(_cs('cancelReservationBtn')), findsOneWidget);
  });

  testWidgets('starý vzhled: úprava — velikosti, termín na webu, storno', (t) async {
    final r = gearRes();
    await pumpV2(t, GearEditScreen(res: r, onBack: () {}, onReload: () async {}),
        size: const Size(412, 3000), v2: false, overrides: gearOverrides([r]), scaffold: false);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byType(GearEditOldView), findsOneWidget);
    expect(find.text(_cs('gearSizesTitle')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('gear-size-boots-44')));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text(_cs('gearSizesFree')), findsOneWidget);
    expect(find.byKey(const ValueKey('gear-edit-dates-web')), findsOneWidget);
    expect(find.byKey(const ValueKey('gear-edit-cancel')), findsOneWidget);
  });
}
