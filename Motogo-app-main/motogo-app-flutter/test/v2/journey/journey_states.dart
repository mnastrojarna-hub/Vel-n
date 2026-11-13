// Journey rig — named start states (MG_JOURNEY_STATE). Each state is the
// data a customer would have on the server: logged in or not, profile,
// documents (gate + OCR stamps), licence groups, bookings, door codes,
// pending payment. The rig turns it into provider overrides
// (journey_overrides.dart) and fake backend answers (journey_backend.dart).
import 'dart:convert';

import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/features/documents/docs_gate_provider.dart';
import 'package:motogo_app/features/documents/document_provider.dart';
import 'package:motogo_app/features/loyalty/loyalty_provider.dart';
import 'package:motogo_app/features/reservations/reservation_models.dart';
import 'package:motogo_app/features/reservations/reservation_provider.dart';

import '../support/fakes_home.dart' show loyaltyAt;
import '../support/fakes_reservations.dart' show code, rday, resv;

enum JourneyState {
  firstLaunch('first_launch'),
  newUserNoDocs('new_user_no_docs'),
  ready('ready'),
  licenceLow('licence_low'),
  unpaidBooking('unpaid_booking'),
  paidUpcoming('paid_upcoming'),
  paidUpcomingNoDocs('paid_upcoming_no_docs'),
  activeRental('active_rental'),
  completed('completed'),
  // Changing a booking (README "Changing a booking").
  paidUpcomingExtFree('paid_upcoming_ext_free'),
  paidUpcomingExtTaken('paid_upcoming_ext_taken'),
  activeRentalExtFree('active_rental_ext_free'),
  activeRentalExtTaken('active_rental_ext_taken'),
  paidUpcomingSwap('paid_upcoming_swap'),
  paidUpcomingSurchargePending('paid_upcoming_surcharge_pending');

  final String id;
  const JourneyState(this.id);

  static JourneyState parse(String? s) =>
      values.firstWhere((v) => v.id == s, orElse: () => throw ArgumentError('Unknown MG_JOURNEY_STATE "$s". '
          'Known: ${values.map((v) => v.id).join(', ')}'));
}

const _gateOk = DocsGateChecklist(
  ok: true, idFront: true, idBack: true, passport: false, dlFront: true, dlBack: true,
  identityOk: true, licenseOk: true, hasDob: true, ageOk: true, expiryOk: true, groupsOk: true,
  licenseExpiry: '2034-05-01', licenseGroups: ['A', 'B'],
);

const _gateNone = DocsGateChecklist(
  ok: false, idFront: false, idBack: false, passport: false, dlFront: false, dlBack: false,
  identityOk: false, licenseOk: false, hasDob: false, ageOk: false, expiryOk: false, groupsOk: false,
);

/// Documents uploaded only partly (OP both sides, ŘP missing) — the codes
/// of a paid booking stay held back.
const _gateMissingDl = DocsGateChecklist(
  ok: false, idFront: true, idBack: true, passport: false, dlFront: false, dlBack: false,
  identityOk: true, licenseOk: false, hasDob: true, ageOk: true, expiryOk: false, groupsOk: false,
);

/// Complete profile (every field the booking validators need).
Map<String, dynamic> _fullProfile(List<String> groups) => {
      'full_name': 'Jan Novák',
      'email': 'jan.novak@example.cz',
      'phone': '+420 777 123 456',
      'street': 'Masarykova 12',
      'zip': '60200',
      'city': 'Brno',
      'country': 'Česká republika',
      'date_of_birth': '1972-05-05',
      'id_number': '123456789',
      'license_number': 'EF123456',
      'license_expiry': '2034-05-01',
      'license_group': groups,
    };

/// Brand-new account: name + e-mail only.
const _newProfile = <String, dynamic>{
  'full_name': 'Petr Dvořák',
  'email': 'petr.dvorak@example.cz',
};

/// Everything one start state means.
class JourneyData {
  final JourneyState state;
  final bool loggedIn;
  final Map<String, dynamic>? profile;
  final DocsGateChecklist? gate;
  final DocsVerification verification;
  final List<Reservation> reservations;
  final Map<String, List<DoorCode>> codes;
  final PendingBooking? pending;
  final LoyaltyStatus? loyalty;

  /// Other customers' bookings: (bike id, first day, last day) as day
  /// offsets from today. The fake backend answers them in
  /// `get_moto_booked_dates` / `check_moto_availability` like the server.
  final List<(String, int, int)> others;

  /// Extra SharedPreferences values on the phone (e.g. a surcharge payment
  /// that was sent and is still being verified).
  final Map<String, Object> prefs;
  const JourneyData({
    required this.state,
    required this.loggedIn,
    this.profile,
    this.gate,
    this.verification = const DocsVerification(),
    this.reservations = const [],
    this.codes = const {},
    this.pending,
    this.loyalty,
    this.others = const [],
    this.prefs = const {},
  });

  DocsScreenStatus get docsStatus => DocsScreenStatus(verification, gate);

  /// JSON the RPC `get_docs_gate_checklist` would answer.
  Map<String, dynamic>? get gateJson {
    final g = gate;
    if (g == null) return null;
    return {
      'ok': g.ok, 'id_front': g.idFront, 'id_back': g.idBack, 'passport': g.passport,
      'dl_front': g.dlFront, 'dl_back': g.dlBack, 'identity_ok': g.identityOk, 'license_ok': g.licenseOk,
      'date_of_birth': g.hasDob ? '1972-05-05' : null, 'age_ok': g.ageOk, 'expiry_ok': g.expiryOk,
      'groups_ok': g.groupsOk, 'license_expiry': g.licenseExpiry, 'license_groups': g.licenseGroups,
      'required_groups': g.requiredGroups,
    };
  }
}

DocsVerification _verified() => DocsVerification(idVerifiedAt: rday(-30), licenseVerifiedAt: rday(-30));

List<DoorCode> _sent() => [code('accessories', '4821'), code('motorcycle', '7395')];
List<DoorCode> _held() => [
      code('accessories', '', sent: false, reason: 'docs_missing'),
      code('motorcycle', '', sent: false, reason: 'docs_missing'),
    ];

/// Pickup 09:00 in the booking-change states: a self-service pickup from
/// 12:00 earns a late-pickup discount that `resv` does not store, so the
/// edit page would show a refund nobody asked for (fixture mismatch).
const _t9 = '09:00:00';

JourneyData journeyData(JourneyState s) {
  final ok = _verified();
  switch (s) {
    case JourneyState.firstLaunch:
      return JourneyData(state: s, loggedIn: false);
    case JourneyState.newUserNoDocs:
      return JourneyData(state: s, loggedIn: true, profile: _newProfile, gate: _gateNone, loyalty: loyaltyAt(1));
    case JourneyState.ready:
      return JourneyData(
          state: s, loggedIn: true, profile: _fullProfile(['A', 'B']), gate: _gateOk, verification: ok, loyalty: loyaltyAt(3));
    case JourneyState.licenceLow:
      return JourneyData(
          state: s,
          loggedIn: true,
          profile: _fullProfile(['A2', 'B']),
          gate: const DocsGateChecklist(
            ok: true, idFront: true, idBack: true, passport: false, dlFront: true, dlBack: true,
            identityOk: true, licenseOk: true, hasDob: true, ageOk: true, expiryOk: true, groupsOk: true,
            licenseExpiry: '2034-05-01', licenseGroups: ['A2', 'B'],
          ),
          verification: ok,
          loyalty: loyaltyAt(3));
    case JourneyState.unpaidBooking:
      final b = resv('u1', status: 'pending', pay: 'unpaid', from: 9, to: 11, self: false, bike: 'BMW R 1200 GS Adventure',
          created: DateTime.now().subtract(const Duration(minutes: 5)));
      return JourneyData(
          state: s, loggedIn: true, profile: _fullProfile(['A', 'B']), gate: _gateOk, verification: ok,
          reservations: [b], pending: PendingBooking(id: b.id, totalPrice: 12027, createdAt: b.createdAt),
          loyalty: loyaltyAt(3));
    case JourneyState.paidUpcoming:
      final b = resv('p1', status: 'reserved', from: 2, to: 4);
      return JourneyData(
          state: s, loggedIn: true, profile: _fullProfile(['A', 'B']), gate: _gateOk, verification: ok,
          reservations: [b], codes: {b.id: _sent()}, loyalty: loyaltyAt(3));
    case JourneyState.paidUpcomingNoDocs:
      final b = resv('p2', status: 'reserved', from: 2, to: 4);
      return JourneyData(
          state: s, loggedIn: true, profile: _fullProfile(['A', 'B']), gate: _gateMissingDl,
          verification: DocsVerification(idVerifiedAt: rday(-30)), reservations: [b], codes: {b.id: _held()},
          loyalty: loyaltyAt(3));
    case JourneyState.activeRental:
      final b = resv('a1', status: 'active', from: -1, to: 2, handedOver: rday(-1));
      return JourneyData(
          state: s, loggedIn: true, profile: _fullProfile(['A', 'B']), gate: _gateOk, verification: ok,
          reservations: [b], codes: {b.id: _sent()}, loyalty: loyaltyAt(3));
    case JourneyState.paidUpcomingExtFree:
    case JourneyState.paidUpcomingExtTaken:
    case JourneyState.paidUpcomingSurchargePending:
      // Husqvarna in 3–6 days (4 days: room to shorten). Taken = the same
      // bike is booked by someone else on days 7–10 (right after).
      final b = resv('e1', status: 'reserved', from: 3, to: 6, pickupTime: _t9);
      final pendingPay = s == JourneyState.paidUpcomingSurchargePending;
      final now = DateTime.now().millisecondsSinceEpoch;
      return JourneyData(
          state: s, loggedIn: true, profile: _fullProfile(['A', 'B']), gate: _gateOk, verification: ok,
          reservations: [b], codes: {b.id: _sent()}, loyalty: loyaltyAt(3),
          others: s == JourneyState.paidUpcomingExtTaken ? const [('m-husq', 7, 10)] : const [],
          // An extension surcharge of this booking was paid 2 min ago and the
          // server has not confirmed it yet (PaymentPendingMarker, kind edit).
          prefs: pendingPay
              ? {
                  'mg_payment_submitted_v2': jsonEncode({
                    b.id: {'at': now - 120000, 'att': now - 120000, 'k': 'edit', 'exp': 16200},
                  }),
                }
              : const {});
    case JourneyState.activeRentalExtFree:
    case JourneyState.activeRentalExtTaken:
      // Riding since yesterday until day 2; taken = days 3–6 booked by someone else.
      final b = resv('x1', status: 'active', from: -1, to: 2, handedOver: rday(-1), pickupTime: _t9);
      return JourneyData(
          state: s, loggedIn: true, profile: _fullProfile(['A', 'B']), gate: _gateOk, verification: ok,
          reservations: [b], codes: {b.id: _sent()}, loyalty: loyaltyAt(3),
          others: s == JourneyState.activeRentalExtTaken ? const [('m-husq', 3, 6)] : const []);
    case JourneyState.paidUpcomingSwap:
      // Licence A2+B. Swap candidates: BMW needs A (licence filter), the
      // Shotgun is booked by someone else on days 4–5, the Yamaha is free.
      final b = resv('w1', status: 'reserved', from: 3, to: 6, pickupTime: _t9);
      return JourneyData(
          state: s, loggedIn: true, profile: _fullProfile(['A2', 'B']),
          gate: const DocsGateChecklist(
            ok: true, idFront: true, idBack: true, passport: false, dlFront: true, dlBack: true,
            identityOk: true, licenseOk: true, hasDob: true, ageOk: true, expiryOk: true, groupsOk: true,
            licenseExpiry: '2034-05-01', licenseGroups: ['A2', 'B'],
          ),
          verification: ok, reservations: [b], codes: {b.id: _sent()}, loyalty: loyaltyAt(3),
          others: const [('m-shot', 4, 5)]);
    case JourneyState.completed:
      final b = resv('c1', status: 'completed', from: -6, to: -4, self: false, bike: 'BMW R 1200 GS Adventure');
      return JourneyData(
          state: s, loggedIn: true, profile: _fullProfile(['A', 'B']), gate: _gateOk, verification: ok,
          reservations: [b], loyalty: loyaltyAt(4));
  }
}
