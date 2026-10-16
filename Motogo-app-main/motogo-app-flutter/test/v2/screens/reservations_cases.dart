// Cases of the Reservations v2 matrix (list / detail / edit), shared by
// reservations_test.dart. Detail and edit views are pumped DIRECTLY with
// the data their seams pass (PLAN §5.2: S screens load in initState).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/core/widgets/pickup_location_link.dart';
import 'package:motogo_app/features/booking/widgets/address_picker.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/documents/booking_doc_viewer.dart';
import 'package:motogo_app/features/reservations/reservation_edit_price_calc.dart';
import 'package:motogo_app/features/reservations/reservation_models.dart';
import 'package:motogo_app/features/reservations/reservation_provider.dart';
import 'package:motogo_app/features/reservations/v2/res_detail_view_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_chooser_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_states_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_view_v2.dart';
import 'package:motogo_app/features/reservations/widgets/reservation_edit_calendar_section.dart';
import 'package:motogo_app/features/reservations/widgets/reservation_edit_extras_section.dart';
import 'package:motogo_app/features/reservations/widgets/reservation_edit_moto_section.dart';
import 'package:motogo_app/features/reservations/widgets/reservation_edit_widgets.dart';

import '../support/fakes_reservations.dart';

typedef ResCase = (Widget Function(), List<Override> Function());

String kPayDetailsLabel(String lang) => translations[lang]?['paymentDetailsTab'] ?? '';
String kHistoryLabel(String lang) => translations[lang]?['v2ResHistory'] ?? '';

Map<String, List<Override> Function()> listCases() {
  final unpaid = resv('u1', status: 'pending', pay: 'unpaid', from: 9, to: 11, bike: 'BMW R 1200 GS Adventure', created: _fresh());
  return {
    'all': () => resOverrides(list: sampleList()),
    'active': () => resOverrides(list: sampleList(), filter: 'aktivni'),
    'upcoming': () => resOverrides(list: sampleList(), filter: 'nadchazejici'),
    'completed': () => resOverrides(list: sampleList(), filter: 'dokoncene'),
    'cancelled': () => resOverrides(list: sampleList(), filter: 'cancelled'),
    'unpaid': () => resOverrides(
        list: [unpaid, ...sampleList()], pending: PendingBooking(id: unpaid.id, totalPrice: 12027, createdAt: _fresh())),
    'verifying': () => resOverrides(
        list: [unpaid],
        pending: PendingBooking(id: unpaid.id, totalPrice: 12027, createdAt: _fresh(), verifying: true)),
    'sos': () => resOverrides(list: [
          resv('s1', status: 'active', from: -1, to: 2, sosReplacement: true, handedOver: rday(-1)),
          resv('s2', status: 'completed', from: -4, to: -2, endedBySos: true),
        ]),
    'filter-empty': () => resOverrides(list: [sampleList()[2]], filter: 'aktivni'),
    'empty': () => resOverrides(),
    'stale': () => resOverrides(list: sampleList(), stale: true),
    'error': () => resOverrides(error: true),
    'loading': () => resOverrides(loading: true),
  };
}

Widget detailView(Reservation r, {List<DoorCode> codes = const [], AsyncValue<List<DoorCode>>? codesAsync, bool stale = false}) =>
    ResDetailV2View(
      res: r,
      doorCodesAsync: codesAsync ?? AsyncData(codes),
      branchFullAddress: r.isSelfService ? 'Boudky, Velké Němčice' : 'Mezná 9, Pelhřimov',
      onStaleRetry: stale ? () {} : null,
      onBack: () {},
      onShowCancelDialog: () {},
      onOpenFinalInvoice: (_, __) async {},
      onOpenContract: (_, __) async {},
      onRestoreBooking: (_, __) async {},
    );

Map<String, ResCase> detailCases() {
  final sent = [code('accessories', '4821'), code('motorcycle', '7395')];
  final held = [
    code('accessories', '', sent: false, reason: null),
    code('motorcycle', '', sent: false, reason: null),
  ];
  final ready = resv('d1', status: 'reserved', from: 0, to: 2);
  final active = resv('d2', status: 'active', from: -1, to: 1, handedOver: rday(-1));
  final unpaid = resv('d3', status: 'pending', pay: 'unpaid', from: 5, to: 7, self: false, bike: 'BMW R 1200 GS Adventure', created: _fresh());
  final docs = {'protocol': const BookingDocSource(signedHtml: '<p>x</p>'), 'contract': const BookingDocSource(signedHtml: '<p>y</p>')};
  return {
    'ready': (() => detailView(ready, codes: sent), () => resOverrides()),
    'late-gate': (
      () => detailView(resv('d4', status: 'reserved', from: 2, to: 4, latePickup: 1907, discount: 500)),
      () => resOverrides()
    ),
    'unpaid': (
      () => detailView(unpaid),
      () => resOverrides(pending: PendingBooking(id: unpaid.id, totalPrice: 12027, createdAt: _fresh()))
    ),
    'verifying': (
      () => detailView(unpaid),
      () => resOverrides(pending: PendingBooking(id: unpaid.id, totalPrice: 12027, createdAt: _fresh(), verifying: true))
    ),
    'docs': (() => detailView(ready, codes: held), () => resOverrides()),
    'active': (() => detailView(active, codes: sent), () => resOverrides(docs: docs)),
    'codes-error': (
      () => detailView(active, codesAsync: AsyncError(Exception('offline'), StackTrace.empty)),
      () => resOverrides()
    ),
    'done-0': (() => detailView(resv('d5', status: 'completed', from: -6, to: -4)), () => resOverrides(docs: docs)),
    'done-2': (() => detailView(resv('d6', status: 'completed', from: -6, to: -4, rating: 2)), () => resOverrides()),
    'done-5': (
      () => detailView(resv('d7', status: 'completed', from: -6, to: -4, rating: 5, ownGear: true)),
      () => resOverrides(docs: docs)
    ),
    'cancelled': (() => detailView(resv('d8', status: 'cancelled', from: 10, to: 12)), () => resOverrides()),
    'delivery': (
      () => detailView(resv('d9', status: 'reserved', from: 4, to: 6, self: false, delivery: true, gear: false)),
      () => resOverrides()
    ),
    'sos': (
      () => detailView(resv('d10', status: 'active', from: -1, to: 2, sosReplacement: true, handedOver: rday(-1)), codes: sent),
      () => resOverrides(gate: false)
    ),
    'stale': (() => detailView(ready, codes: sent, stale: true), () => resOverrides()),
  };
}

const _prices = DayPrices(mon: 3543, tue: 3543, wed: 3543, thu: 3543, fri: 4620, sat: 4997, sun: 4997);

EditPriceCalc _calc(Reservation b, {int addDays = 0}) => EditPriceCalc(
      booking: b,
      newStart: b.startDate,
      newEnd: DateTime(b.endDate.year, b.endDate.month, b.endDate.day + addDays),
      motoPrices: _prices,
      newMotoId: null,
      pickupDelivFee: 0,
      returnDelivFee: 0,
      selectedExtras: const {},
      pickupMethod: 'store',
      returnMethod: 'store',
      pickupTime: '12:00',
      returnTime: '23:59',
    );

Widget editView(
  Reservation b, {
  String tab = 'extend',
  ResEditIntent? intent,
  int addDays = 0,
  bool active = false,
  int? stornoPct,
  List<String> missing = const [],
}) {
  final calc = _calc(b, addDays: addDays);
  final datesOrSwap = tab == 'move' || tab == 'swap';
  return ResEditV2View(
    booking: b,
    tab: tab,
    isActive: active,
    canMove: !active,
    canSwap: true,
    returnTimeAvailable: false,
    calc: calc,
    sections: ResEditV2Sections(
      swap: tab == 'swap' ? Container(height: 240, color: const Color(0xFFFFFFFF)) : null,
      calendar: tab == 'swap'
          ? null
          : EditCalendarSection(
              tab: tab,
              isActive: active,
              origStart: b.startDate,
              origEnd: b.endDate,
              newStart: calc.newStart,
              newEnd: calc.newEnd,
              diffDays: calc.diffDays,
              shortenDir: tab == 'shorten' ? 'end' : null,
              calendarInstruction: 'Klikni na den před nebo po rezervaci',
              motoName: b.motoName,
              shortId: b.shortId,
              bookedDates: const [],
              onDatesChanged: (_, __) {},
              onError: (_) {},
              onShortenStart: () {},
              onShortenEnd: () {},
            ),
      pickupPlace: active || datesOrSwap
          ? null
          : AddressPickerWidget(
              label: 'Vyzvednutí',
              method: 'store',
              branchLabel: 'Boudky, Velké Němčice',
              onMethodChanged: (_) {},
              onAddressChanged: (_) {},
              onDeliveryFeeChanged: (_) {},
            ),
      pickupTime: active || datesOrSwap ? null : EditTimePicker(label: 'ČAS VYZVEDNUTÍ', value: '12:00', onChanged: (_) {}),
      pickupLegacyLine: false,
      pickupSelfServiceHint: true,
      returnPlace: datesOrSwap
          ? null
          : AddressPickerWidget(
              label: 'Vrácení',
              isPickup: false,
              method: 'store',
              branchLabel: 'Boudky, Velké Němčice',
              onMethodChanged: (_) {},
              onAddressChanged: (_) {},
              onDeliveryFeeChanged: (_) {},
            ),
      returnTime: null,
      moto: active || datesOrSwap
          ? null
          : EditMotoChangeSection(
              bookingId: b.id,
              rangeStart: b.startDate,
              rangeEnd: b.endDate,
              currentMotoName: b.motoName,
              currentMotoId: b.motoId,
              newMotoId: null,
              expanded: false,
              userLicenseGroups: const ['A'],
              onMotoSelected: (_) {},
              onToggleExpanded: () {},
            ),
      extras: active || datesOrSwap
          ? null
          : EditExtrasSection(
              selectedExtras: const {},
              pickupMethod: 'store',
              returnMethod: 'store',
              selfService: true,
              loyaltyLevel: 3,
              helmetSize: 'L',
              jacketSize: 'XL',
              pantsSize: null,
              bootsSize: '43',
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
            ),
    ),
    stornoPct: stornoPct,
    missingSizes: missing,
    saveLabel: tab == 'swap' ? null : (tab == 'move' ? 'Posunout zdarma' : 'POKRAČOVAT K PLATBĚ (+4 997 Kč)'),
    onSave: addDays != 0 || tab == 'move' ? () {} : null,
    saving: false,
    onBack: () {},
    onSelectExtend: () {},
    onSelectShorten: () {},
    onSelectMove: () {},
    onSelectSwap: () {},
    initialIntent: intent,
  );
}

Map<String, ResCase> editCases() {
  final b = resv('e1', status: 'reserved', from: 4, to: 6);
  final a = resv('e2', status: 'active', from: -1, to: 1, handedOver: rday(-1));
  List<Override> o() => resOverrides();
  return {
    'chooser': (() => editView(b), o),
    'chooser-active': (() => editView(a, active: true), o),
    'chooser-changed': (() => editView(b, addDays: 1), o),
    'extend': (() => editView(b, intent: ResEditIntent.extend, addDays: 1), o),
    'shorten': (() => editView(b, tab: 'shorten', intent: ResEditIntent.shorten, addDays: -1, stornoPct: 50), o),
    'move': (() => editView(b, tab: 'move', intent: ResEditIntent.move), o),
    'swap': (() => editView(b, tab: 'swap', intent: ResEditIntent.swap), o),
    'time': (() => editView(b, intent: ResEditIntent.time), o),
    'place': (() => editView(b, intent: ResEditIntent.place), o),
    'moto': (() => editView(b, intent: ResEditIntent.moto), o),
    'gear': (() => editView(b, intent: ResEditIntent.gear, missing: const ['Helma', 'Bunda']), o),
    'active-extend': (() => editView(a, active: true, intent: ResEditIntent.extend, addDays: 2), o),
    'confirm': (
      () => EditConfirmV2(
            title: 'Rezervace upravena',
            message: 'Změny byly uloženy. Potvrzení ti přijde e-mailem.',
            isRefund: false,
            pickup: const PickupInfo(name: 'Velké Němčice', address: 'Boudky, Velké Němčice', lat: 49.0043, lng: 16.6721),
            onDone: () {},
          ),
      o
    ),
    'confirm-refund': (
      () => const EditConfirmV2(
            title: 'Rezervace zkrácena',
            message: 'Rozdíl 3 514 Kč ti vrátíme na kartu, kterou se platilo.',
            isRefund: true,
            pickup: null,
            onDone: _noop,
          ),
      o
    ),
    'load-error': (() => const EditStateV2(onBack: _noop, error: 'Rezervaci se nepodařilo načíst.', onRetry: _noop), o),
    'loading': (() => const EditStateV2(onBack: _noop), o),
  };
}

void _noop() {}

/// Unpaid bookings older than 30 min read as cancelled (server window).
DateTime _fresh() => DateTime.now().subtract(const Duration(minutes: 5));
