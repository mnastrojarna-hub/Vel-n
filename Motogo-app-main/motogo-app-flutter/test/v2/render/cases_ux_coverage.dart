// verify:coverage — surfaces with the flag ON that no other render case
// draws with the REAL widget (the edit fixtures use placeholders for the
// swap section; the SOS replacement fixture uses placeholders for the
// address widgets): reservation edit intents "Výměna motorky" (swap, its
// date picker), "Jiná motorka" (expanded list), "Výbava a doplňky" (boot /
// passenger sheets), "Místo předání" (delivery), the paid-change banner of
// the reservation detail, the SOS replacement delivery address and the
// date dropdown menu of the register form.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/paid_change_queue.dart';
import 'package:motogo_app/core/widgets/address_autocomplete_field.dart';
import 'package:motogo_app/features/auth/v2/register_view_v2.dart';
import 'package:motogo_app/features/booking/booking_ui_helpers.dart' show showAddrBottomSheet;
import 'package:motogo_app/features/booking/widgets/address_picker.dart';
import 'package:motogo_app/features/loyalty/v2/loyalty_screen_v2.dart';
import 'package:motogo_app/features/reservations/reservation_edit_price_calc.dart';
import 'package:motogo_app/features/reservations/reservation_models.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_address_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_chooser_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_view_v2.dart';
import 'package:motogo_app/features/reservations/widgets/res_modification_history.dart';
import 'package:motogo_app/features/reservations/widgets/reservation_edit_extras_section.dart';
import 'package:motogo_app/features/reservations/widgets/reservation_edit_moto_section.dart';
import 'package:motogo_app/features/reservations/widgets/reservation_swap_section.dart';
import 'package:motogo_app/features/sos/sos_here_address.dart';
import 'package:motogo_app/features/sos/v2/sos_replacement_view_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/reservations_cases.dart';
import '../support/fakes_history.dart';
import '../support/fakes_leaderboard.dart';
import '../support/fakes_reservations.dart';
import 'cases_core.dart' show launcher, tapOpen;
import 'cases_ux_auth_sos_misc.dart' show asmBase, asmMotos, asmRegModel;
import 'render_harness.dart';

void _n() {}

Widget _edit(Reservation b, ResEditIntent intent, {Widget? swap, Widget? moto, Widget? extras, Widget? pickupPlace}) {
  final EditPriceCalc calc = editCalc(b);
  return ResEditV2View(
    booking: b,
    tab: intent == ResEditIntent.swap ? 'swap' : 'extend',
    isActive: false,
    canMove: true,
    canSwap: true,
    returnTimeAvailable: false,
    calc: calc,
    sections: ResEditV2Sections(
      swap: swap,
      calendar: null,
      pickupPlace: pickupPlace,
      pickupTime: null,
      pickupLegacyLine: false,
      pickupSelfServiceHint: false,
      returnPlace: null,
      returnTime: null,
      moto: moto,
      extras: extras,
    ),
    stornoPct: null,
    missingSizes: const [],
    saveLabel: intent == ResEditIntent.swap ? null : 'Uložit změny',
    savePrice: null,
    saveContext: null,
    onSave: null,
    saving: false,
    onBack: _n,
    onSelectExtend: _n,
    onSelectShorten: _n,
    onSelectMove: _n,
    onSelectSwap: _n,
    initialIntent: intent,
  );
}

Reservation _b() => resv('cv1', status: 'reserved', from: 4, to: 6);

Widget _extras() => EditExtrasSection(
      selectedExtras: const {},
      pickupMethod: 'store',
      returnMethod: 'store',
      selfService: true,
      loyaltyLevel: 1,
      helmetSize: 'L',
      jacketSize: 'XL',
      pantsSize: null,
      bootsSize: null,
      glovesSize: 'L',
      passengerHelmetSize: null,
      passengerJacketSize: null,
      passengerPantsSize: null,
      passengerBootsSize: null,
      onPassengerGlovesSize: (_) {},
      onExtrasChanged: (_) {},
      onOwnGearChanged: (_) {},
      onHelmetSize: (_) {},
      onJacketSize: (_) {},
      onPantsSize: (_) {},
      onBootsSize: (_) {},
      onGlovesSize: (_) {},
      onPassengerHelmetSize: (_) {},
      onPassengerJacketSize: (_) {},
      onPassengerPantsSize: (_) {},
      onPassengerBootsSize: (_) {},
    );

Future<void> _tap(WidgetTester t, String text) async {
  final f = find.text(text);
  if (f.evaluate().isEmpty) return;
  await t.ensureVisible(f.first);
  await t.pump();
  await t.tap(f.first, warnIfMissed: false);
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

Future<void> _scroll(WidgetTester t) async {
  final s = find.byType(Scrollable);
  if (s.evaluate().isEmpty) return;
  await t.drag(s.first, const Offset(0, -900), warnIfMissed: false);
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Widget _paidChange(Map<String, Object> entry) {
  SharedPreferences.setMockInitialValues({
    PaidChangeQueue.storeKey: jsonEncode({entry['k']: entry}),
  });
  return detailView(resv('pc1', status: 'reserved', from: 5, to: 7));
}

int get _nowMs => DateTime.now().millisecondsSinceEpoch;

List<RenderCase> coverageUxCases() => [
      RenderCase(
          'cov',
          'edit',
          'swap',
          () => _edit(_b(), ResEditIntent.swap,
              swap: SwapMotoSection(booking: _b(), userLicenseGroups: const ['A'], onSwapped: (_, __, ___, ____) {})),
          () => resOverrides()),
      RenderCase(
          'cov',
          'edit',
          'swap_date_picker',
          () => _edit(_b(), ResEditIntent.swap,
              swap: SwapMotoSection(booking: _b(), userLicenseGroups: const ['A'], onSwapped: (_, __, ___, ____) {})),
          () => resOverrides(),
          after: (t) async {
            // v2: the date box opens the calendar sheet (old: dialog icon).
            final v2 = find.byKey(const ValueKey('swap-v2-date'));
            final f = v2.evaluate().isNotEmpty ? v2 : find.byIcon(Icons.edit_calendar);
            if (f.evaluate().isEmpty) return;
            await t.ensureVisible(f.first);
            await t.tap(f.first, warnIfMissed: false);
            await t.pump();
            await t.pump(const Duration(milliseconds: 600));
          }),
      RenderCase(
          'cov',
          'edit',
          'moto_expanded',
          () => _edit(_b(), ResEditIntent.moto,
              moto: EditMotoChangeSection(
                bookingId: 'cv1',
                rangeStart: _b().startDate,
                rangeEnd: _b().endDate,
                currentMotoName: 'Husqvarna 701 SM',
                currentMotoId: 'x',
                newMotoId: null,
                expanded: true,
                userLicenseGroups: const ['A'],
                onMotoSelected: (_) {},
                onToggleExpanded: _n,
              )),
          () => resOverrides()),
      RenderCase('cov', 'edit', 'gear_boots_sheet', () => _edit(_b(), ResEditIntent.gear, extras: _extras()),
          () => resOverrides(),
          after: (t) => _tap(t, 'Boty řidiče')),
      RenderCase('cov', 'edit', 'gear_passenger_sheet', () => _edit(_b(), ResEditIntent.gear, extras: _extras()),
          () => resOverrides(),
          after: (t) => _tap(t, 'Výbava spolujezdce')),
      RenderCase(
          'cov',
          'edit',
          'place_delivery',
          () => _edit(_b(), ResEditIntent.place,
              pickupPlace: AddressPickerWidget(
                label: 'Vyzvednutí',
                method: 'delivery',
                branchLabel: 'Boudky, Velké Němčice',
                currentAddress: 'Masarykova 12, Brno',
                rowBuilder: (c, d) => ResEditAddressRowV2(data: d),
                onMethodChanged: (_) {},
                onAddressChanged: (_) {},
                onDeliveryFeeChanged: (_) {},
              )),
          () => resOverrides()),
      RenderCase(
          'cov',
          'detail',
          'paid_change_pending',
          () => _paidChange({'k': 'pc-1', 'b': 'pc1aaaaaaa-1111-2222-3333-444455556666', 't': 'swap', 'c': 990, 'p': true, 'at': _nowMs, 's': 'pending'}),
          () => resOverrides()),
      RenderCase(
          'cov',
          'detail',
          'paid_change_failed',
          () => _paidChange({
                'k': 'pc-2',
                'b': 'pc1aaaaaaa-1111-2222-3333-444455556666',
                't': 'swap',
                'c': 990,
                'p': true,
                'at': _nowMs,
                's': 'failed',
                'f': {'reason': 'new_moto_unavailable', 'refund': 'auto', 'amount': 990},
              }),
          () => resOverrides()),
      RenderCase(
          'cov',
          'sos',
          'replacement_address',
          () => SosReplacementViewV2(
              motos: AsyncValue.data(asmMotos(2)),
              selectedId: 'm1',
              onSelect: (_) {},
              loading: false,
              onConfirm: _n,
              onBack: _n,
              hereAddress: SosHereAddress(onPick: (_) {}, locate: () async => null),
              addressField: AddressAutocompleteField(onSelected: (_) {}, hint: 'Zadej obec nebo ulici'),
              error: (_) => const SizedBox(),
              callButton: const SizedBox()),
          asmBase,
          scaffold: false,
          after: _scroll),
      RenderCase('cov', 'register', 'date_menu', () => RegisterViewV2(m: asmRegModel(1)), asmBase,
          scaffold: false,
          after: (t) => _tap(t, 'Den')),
      // fix:r2 — "Historie rezervace" in the v2 look (ResHistoryV2).
      RenderCase('cov', 'history', 'mods',
          () => SingleChildScrollView(padding: const EdgeInsets.all(16), child: ResModificationHistory(res: histModsRes())),
          () => resOverrides()),
      RenderCase(
          'cov',
          'history',
          'cancel_sos',
          () => SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ResModificationHistory(res: histCancelSosRes(), sosIncidents: histIncidents())),
          () => resOverrides()),
      // fix:r2 — "Žebříček jezdců" (flag loyalty_leaderboard) in the v2 look.
      RenderCase('cov', 'loyalty', 'leaderboard', () => const LoyaltyScreenV2(), () => leaderboardOverrides(),
          level: 6, scaffold: false),
      RenderCase('cov', 'loyalty', 'leaderboard_empty', () => const LoyaltyScreenV2(),
          () => leaderboardOverrides(empty: true, nick: null),
          level: 6, scaffold: false),
      RenderCase('cov', 'booking', 'address_sheet',
          () => launcher((c) => showAddrBottomSheet(c, 'Adresa přistavení', 'Brno', 'Masarykova 12', (_, __) {})),
          () => resOverrides(),
          after: tapOpen),
    ];
