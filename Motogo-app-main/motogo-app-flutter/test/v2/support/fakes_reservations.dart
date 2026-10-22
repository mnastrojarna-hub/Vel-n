// Fixtures + provider overrides for the Reservations v2 tests (PLAN §5.2):
// V22 sample bookings (Husqvarna 701 SM Velké Němčice self-service, BMW
// R 1200 GS Adventure Mezná), every Supabase-backed provider faked.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/i18n/translations_ext_54_v2_reservations_a.dart';
import 'package:motogo_app/core/i18n/translations_ext_54_v2_reservations_b.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/documents/booking_doc_viewer.dart';
import 'package:motogo_app/features/loyalty/loyalty_provider.dart';
import 'package:motogo_app/features/reservations/booking_gate_provider.dart';
import 'package:motogo_app/features/reservations/reservation_models.dart';
import 'package:motogo_app/features/reservations/reservation_provider.dart';
import 'package:motogo_app/features/reservations/widgets/res_payment_details_tab.dart';
import 'package:motogo_app/features/routes/ride_model.dart';
import 'package:motogo_app/features/routes/ride_provider.dart';

import 'fakes_home.dart' show kLoyalty3, kMotos;

/// Registers the Reservations v2 strings in the global table (idempotent) —
/// the integration step registers them in translations.dart for the app.
void registerReservationStrings() {
  for (final part in [translationsExt54V2ReservationsA, translationsExt54V2ReservationsB]) {
    part.forEach((lang, map) => translations.putIfAbsent(lang, () => {}).addAll(map));
  }
}

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

DateTime rday(int offset) {
  final t = _today();
  return DateTime(t.year, t.month, t.day + offset);
}

/// One booking. [self] = Velké Němčice self-service, else Mezná staffed.
Reservation resv(
  String id, {
  required String status,
  String pay = 'paid',
  required int from,
  required int to,
  bool self = true,
  bool delivery = false,
  int? rating,
  String bike = 'Husqvarna 701 SM',
  bool gear = true,
  bool ownGear = false,
  double? latePickup,
  double? discount,
  bool sosReplacement = false,
  bool endedBySos = false,
  String pickupTime = '12:00:00',
  DateTime? handedOver,
  DateTime? created,
}) =>
    Reservation(
      id: '${id}aaaaaaa-1111-2222-3333-444455556666',
      motoId: 'm-husq',
      motoName: bike,
      category: 'supermoto',
      branchName: self ? 'Velké Němčice' : 'Mezná',
      branchAddress: self ? 'Boudky' : 'Mezná 9',
      branchCity: self ? 'Velké Němčice' : 'Pelhřimov',
      branchType: self ? 'samoobslužná' : 'obslužná',
      branchLat: 49.0043,
      branchLng: 16.6721,
      status: status,
      paymentStatus: pay,
      startDate: rday(from),
      endDate: rday(to),
      pickupTime: pickupTime,
      returnTime: self ? '23:59:00' : '19:00:00',
      pickupMethod: delivery ? 'delivery' : 'branch',
      pickupAddress: delivery ? 'Masarykova 12, 602 00 Brno' : null,
      returnMethod: 'branch',
      totalPrice: 12027,
      deliveryFee: delivery ? 1480 : null,
      extrasPrice: 400,
      latePickupDiscount: latePickup,
      discountAmount: discount,
      discountCode: discount == null ? null : 'DEMO',
      loyaltyDiscountAmount: 361,
      bookingSource: 'app',
      rating: rating,
      ratedAt: rating == null ? null : rday(to),
      sosReplacement: sosReplacement,
      endedBySos: endedBySos,
      helmetSize: gear && !ownGear ? 'L' : null,
      jacketSize: gear && !ownGear ? 'XL' : null,
      glovesSize: gear && !ownGear ? 'L' : null,
      bootsSize: gear ? '43' : null,
      passengerHelmetSize: gear ? 'M' : null,
      ownGear: ownGear,
      handoverProtocolFilledAt: handedOver,
      createdAt: created ?? DateTime.now().subtract(const Duration(days: 9)),
    );

/// Sample list (4 bookings, V22 board "4 rezervace").
List<Reservation> sampleList() => [
      resv('a1', status: 'active', from: -1, to: 1, handedOver: rday(-1)),
      resv('a2', status: 'reserved', from: 6, to: 8, self: false, bike: 'BMW R 1200 GS Adventure'),
      resv('a3', status: 'completed', from: -12, to: -10, rating: 5),
      resv('a4', status: 'cancelled', from: 20, to: 22, bike: 'Royal Enfield Shotgun 650'),
    ];

DoorCode code(String type, String value, {bool sent = true, String? reason}) => DoorCode(
      id: '$type-$value',
      codeType: type,
      doorCode: sent ? value : '',
      isActive: true,
      sentToCustomer: sent,
      withheldReason: reason,
    );

/// Everything the list / detail views read, faked.
List<Override> resOverrides({
  List<Reservation> list = const [],
  PendingBooking? pending,
  String filter = 'all',
  bool loading = false,
  bool error = false,
  bool stale = false,
  bool gate = true,
  Map<String, BookingDocSource> docs = const {},
  List<SosIncident> sos = const [],
  List<UserRide> rides = const [],
}) =>
    [
      reservationsProvider.overrideWith((ref) {
        if (loading) return StreamController<List<Reservation>>().stream;
        if (error) return Stream<List<Reservation>>.error(Exception('offline'));
        if (stale) {
          return Stream<List<Reservation>>.multi((c) {
            c.add(list);
            c.addError(Exception('offline'));
          });
        }
        return Stream.value(list);
      }),
      resFilterProvider.overrideWith((ref) => filter),
      pendingBookingFabProvider.overrideWith((ref) => Stream.value(pending)),
      loyaltyStatusProvider.overrideWith((ref) async => kLoyalty3),
      googleReviewUrlProvider.overrideWith((ref) async => 'https://g.page/r/test/review'),
      bookingGateInfoProvider.overrideWith(
          (ref, id) async => gate ? const BookingGateInfo(hasGate: true, gateCode: '2580', lockerDoor: 8) : BookingGateInfo.none),
      bookingDocsProvider.overrideWith((ref, id) async => docs),
      sosIncidentsProvider.overrideWith((ref, id) async => sos),
      bookingRidesProvider.overrideWith((ref, id) async => rides),
      paymentDetailsProvider.overrideWith((ref, id) async => const PaymentDetails({
            'payment_method': 'card',
            'card_brand': 'visa',
            'card_last4': '4242',
            'stripe_payment_intent_id': 'pi_3Qtest1234567890',
          }, [])),
      motorcyclesProvider.overrideWith((ref) => Stream.value(kMotos)),
    ];
