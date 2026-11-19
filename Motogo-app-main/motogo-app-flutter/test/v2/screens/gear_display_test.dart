// 5.0.2 výpůjčka JEN výbavy — karta, detail a úprava v NOVÉM vzhledu (v2):
// titulek „Výpůjčka výbavy“, souhrn kusů, kód šatny + „protokol nejdřív“,
// kroky na displeji, doklad totožnosti, zaplacení rozdělané výpůjčky;
// žádné SOS, hodnocení, obnova ani motorka (GEAR_RENTAL_APP.md §5).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/currency.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/gear_rental/gear_contract.dart';
import 'package:motogo_app/features/reservations/gear/gear_booking_api.dart';
import 'package:motogo_app/features/reservations/gear/gear_edit_screen.dart';
import 'package:motogo_app/features/reservations/reservation_models.dart';
import 'package:motogo_app/features/reservations/reservation_provider.dart';
import 'package:motogo_app/features/reservations/v2/reservation_card_v2.dart';
import 'package:motogo_app/features/reservations/widgets/res_detail_tab_content.dart';
import 'package:motogo_app/features/reservations/widgets/res_rating_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_reservations.dart';
import '../support/v2_harness.dart';

String _cs(String k) => AppTranslations.of('cs').tr(k);

String _d(int offset) {
  final n = DateTime.now().add(Duration(days: offset));
  return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

/// Výpůjčka výbavy ve tvaru RPC get_my_gear_bookings.
Reservation gearRes({String status = 'reserved', String pay = 'paid', int from = 5, int to = 6, bool self = true}) =>
    Reservation.fromGearRpc({
      'id': 'gear0000-1111-2222-3333-4444555566$from$to'.substring(0, 36),
      'status': status,
      'payment_status': pay,
      'booking_source': 'web',
      'start_date': _d(from),
      'end_date': _d(to),
      'pickup_time': '10:00',
      'branch': {
        'id': 'br',
        'name': self ? 'MotoGo24 Velké Němčice' : 'MotoGo24 Mezná',
        'address': self ? 'Boudky' : 'Mezná 9',
        'city': self ? 'Velké Němčice' : 'Pelhřimov',
        'type': self ? 'samoobslužná' : 'obslužná',
        'gps_lat': 49.0,
        'gps_lng': 16.6,
      },
      'lines': [
        {'key': 'set_no_boots', 'kind': 'set', 'label': 'Komplet bez bot', 'includes': ['helmet', 'jacket', 'pants', 'gloves'],
          'sizes': {'helmet': 'M', 'jacket': 'L', 'pants': 'L', 'gloves': 'M'}, 'price_per_day': 350},
        {'key': 'boots', 'kind': 'item', 'label': 'Boty', 'includes': ['boots'], 'sizes': {'boots': '43'}, 'price_per_day': 80},
      ],
      'per_day': 430,
      'total': 760,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });

const kGearPrices = [
  GearPrice(key: 'helmet', kind: 'item', label: 'Helma', sizes: ['S', 'M', 'L', 'XL'], perDay: 100),
  GearPrice(key: 'jacket', kind: 'item', label: 'Bunda', sizes: ['M', 'L', 'XL'], perDay: 100),
  GearPrice(key: 'pants', kind: 'item', label: 'Kalhoty', sizes: ['M', 'L'], perDay: 100),
  GearPrice(key: 'gloves', kind: 'item', label: 'Rukavice', sizes: ['M', 'L'], perDay: 50),
  GearPrice(key: 'boots', kind: 'item', label: 'Boty', sizes: ['42', '43', '44'], perDay: 80),
];

List<Override> gearOverrides(List<Reservation> list, {String? docs, bool appVisible = true}) => [
      ...resOverrides(list: list),
      gearDocsStatusProvider.overrideWith((ref, id) async => docs),
      gearPricesProvider.overrideWith((ref) async => kGearPrices),
      gearRentalSettingsProvider.overrideWith((ref) async => GearRentalSettings(appVisible: appVisible)),
    ];

Widget detail(Reservation r, {List<DoorCode> codes = const []}) => CustomScrollView(slivers: [
      ResDetailTabContent(
        res: r,
        doorCodesAsync: AsyncData(codes),
        statusColor: Colors.green,
        statusTitle: 'Nadcházející',
        branchFullAddress: '${r.branchAddress}, ${r.branchCity}',
        onShowCancelDialog: () {},
        onOpenFinalInvoice: (_, __) async {},
        onOpenContract: (_, __) async {},
        onRestoreBooking: (_, __) async {},
      ),
    ]);

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerReservationStrings();
  });
  setUp(() {
    MgMotion.resetSession();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('karta: titulek výbavy, souhrn kusů, pobočka; hotová bez hodnocení, zrušená bez obnovy', (t) async {
    final up = gearRes();
    await pumpV2(t, ReservationCardV2(reservation: up, onTap: () {}, onEdit: () {}),
        size: const Size(360, 780), overrides: gearOverrides([up]));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Výpůjčka výbavy'), findsOneWidget);
    expect(find.text('Komplet bez bot (M, L, L, M) · Boty 43'), findsOneWidget);
    expect(find.textContaining('Velké Němčice'), findsOneWidget);
    expect(find.textContaining('MotoGo24'), findsNothing);
    expect(find.text('SOS'), findsNothing);

    final done = gearRes(status: 'completed', from: -4, to: -3);
    await pumpV2(t, ReservationCardV2(reservation: done, onTap: () {}), overrides: gearOverrides([done]));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text(_cs('rateBtn')), findsNothing);
    final gone = gearRes(status: 'cancelled');
    await pumpV2(t, ReservationCardV2(reservation: gone, onTap: () {}, onRestore: () {}), overrides: gearOverrides([gone]));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text(_cs('restoreBtn')), findsNothing);
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('detail v termínu: jen kód šatny + „protokol nejdřív“, kroky výbavy; žádné SOS ani hodnocení', (t) async {
    final r = gearRes(status: 'reserved', from: 0, to: 1);
    await pumpV2(t, detail(r, codes: [code('accessories', '4321')]),
        size: const Size(412, 4000), overrides: gearOverrides([r]));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('4321'), findsOneWidget);
    expect(find.text(_cs('lockerCodeDoor').replaceAll('{n}', '8')), findsOneWidget);
    expect(find.text(_cs('gearProtocolFirst')), findsOneWidget);
    expect(find.text(_cs('motoCode')), findsNothing);
    expect(find.text(_cs('gearItems').toUpperCase()), findsOneWidget);
    expect(find.textContaining('Komplet bez bot'), findsOneWidget);
    expect(find.text(_cs('gearPlaceLabel')), findsOneWidget);
    expect(find.byType(ResRatingCard), findsNothing);
    expect(find.text(_cs('sosTitle')), findsNothing);
    expect(find.text(_cs('resCategory')), findsNothing);
    expect(find.text(_cs('bookAgain')), findsNothing);
    // Doklady OK (check_booking_docs_status_for = NULL).
    expect(find.byKey(const ValueKey('gear-docs-ok')), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('chybí doklad: výzva jen k OP / pasu s tlačítkem nahrání', (t) async {
    final r = gearRes();
    await pumpV2(t, detail(r), size: const Size(412, 4000), overrides: gearOverrides([r], docs: 'Chybí OP (líc a rub) nebo pas'));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('gear-docs-missing')), findsOneWidget);
    expect(find.byKey(const ValueKey('gear-docs-btn')), findsOneWidget);
    expect(find.textContaining(_cs('gearDocsIdOnly')), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('nezaplacená: „Zaplatit 760 Kč“ v appce, při vypnutém app_visible web', (t) async {
    final r = gearRes(status: 'pending', pay: 'unpaid');
    await pumpV2(t, detail(r), size: const Size(412, 4000), overrides: gearOverrides([r]));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text(_cs('gearPendingTitle')), findsOneWidget);
    expect(find.text(_cs('gearPayNow').replaceAll('{amount}', Money.czk(760))), findsOneWidget);
    await t.pumpWidget(const SizedBox()); // nový ProviderScope (jiné nastavení)
    await pumpV2(t, detail(r), size: const Size(412, 4000), overrides: gearOverrides([r], appVisible: false));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text(_cs('gearPayWeb')), findsOneWidget);
    // Nezaplacenou nelze upravit ani stornovat (web: až po zaplacení).
    expect(find.text(_cs('cancelReservationBtn')), findsNothing);
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('úprava: velikosti z ceníku, výběr povolí Uložit; termín na webu, odebrat kus, storno', (t) async {
    final r = gearRes();
    await pumpV2(t, GearEditScreen(res: r, onBack: () {}, onReload: () async {}),
        size: const Size(412, 3000), overrides: gearOverrides([r]));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('gear-sizes-v2')), findsOneWidget);
    MgCta save() => t.widget<MgCta>(find.byKey(const ValueKey('gear-sizes-save')));
    expect(save().enabled, isFalse);
    await t.tap(find.byKey(const ValueKey('gear-size-helmet-L')));
    await t.pump(const Duration(milliseconds: 300));
    expect(save().enabled, isTrue);
    expect(find.text(_cs('gearSizesFree')), findsOneWidget);
    expect(find.byKey(const ValueKey('gear-remove-v2')), findsOneWidget);
    expect(find.byKey(const ValueKey('gear-edit-dates-web')), findsOneWidget);
    expect(find.text(_cs('gearEditDatesWebHint')), findsOneWidget);
    expect(find.byKey(const ValueKey('gear-edit-cancel')), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
  });
}
