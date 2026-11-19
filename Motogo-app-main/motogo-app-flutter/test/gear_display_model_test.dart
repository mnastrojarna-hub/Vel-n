// 5.0.2 výpůjčka JEN výbavy — model, sloučení s RPC, pravidla (DISPLAY).
// GEAR_RENTAL_APP.md §4/§5, GEAR_RENTAL_APP_EDIT.md §9.
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/features/booking/booking_validator.dart';
import 'package:motogo_app/features/documents/docs_gate_provider.dart';
import 'package:motogo_app/features/documents/document_provider.dart';
import 'package:motogo_app/features/home/v2/home_state.dart';
import 'package:motogo_app/features/reservations/gear/gear_docs_scope.dart';
import 'package:motogo_app/features/reservations/gear/gear_edit_api.dart';
import 'package:motogo_app/features/reservations/gear/gear_links.dart';
import 'package:motogo_app/features/reservations/gear/gear_models.dart';
import 'package:motogo_app/features/reservations/reservation_models.dart';
import 'package:motogo_app/features/reservations/reservation_provider.dart' show mergeGearBookings;

String _d(int offset) {
  final n = DateTime.now().add(Duration(days: offset));
  return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

const _lines = [
  {
    'key': 'set_no_boots',
    'kind': 'set',
    'label': 'Komplet bez bot',
    'includes': ['helmet', 'jacket', 'pants', 'gloves'],
    'sizes': {'helmet': 'M', 'jacket': 'L', 'pants': 'L', 'gloves': 'M'},
    'price_per_day': 350,
    'total': 700,
  },
  {
    'key': 'boots',
    'kind': 'item',
    'label': 'Boty',
    'includes': ['boots'],
    'sizes': {'boots': '43'},
    'price_per_day': 80,
    'total': 160,
  },
];

Map<String, dynamic> _rpc({String status = 'reserved', String pay = 'paid', int from = 5, int to = 6, String type = 'samoobslužná'}) => {
      'id': 'gear0000-1111-2222-3333-444455556666',
      'booking_number': '55556666',
      'booking_kind': 'gear',
      'status': status,
      'payment_status': pay,
      'booking_source': 'web',
      'start_date': _d(from),
      'end_date': _d(to),
      'pickup_time': '10:00',
      'branch': {'id': 'br-vn', 'name': 'MotoGo24 Velké Němčice', 'address': 'Boudky', 'city': 'Velké Němčice', 'type': type, 'gps_lat': 49.0, 'gps_lng': 16.6},
      'lines': _lines,
      'per_day': 430,
      'total': 760,
      'voucher_amount': 100,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

Reservation _moto(String id, {int from = 5, int to = 6}) => Reservation.fromJson({
      'id': '${id}0000-1111-2222-3333-444455556666',
      'moto_id': 'm1',
      'status': 'reserved',
      'payment_status': 'paid',
      'start_date': _d(from),
      'end_date': _d(to),
      'total_price': 5000,
      'created_at': DateTime.now().toIso8601String(),
      'motorcycles': {'model': 'BMW R 1250 GS', 'branches': {'name': 'Mezná', 'type': 'obslužná', 'gps_lat': 1.0, 'gps_lng': 2.0}},
      'booking_branch': {'name': 'Jiná', 'type': 'samoobslužná'},
    });

void main() {
  final cs = AppTranslations.of('cs');

  group('model', () {
    test('fromJson gear: pobočka z booking_branch, název výbavy, řádky, cena/den', () {
      final r = Reservation.fromJson({
        'id': 'gear1111-1111-2222-3333-444455556666',
        'moto_id': null,
        'booking_kind': 'gear',
        'status': 'reserved',
        'payment_status': 'paid',
        'start_date': '${_d(3)}T00:00:00+00:00',
        'end_date': '${_d(4)}T00:00:00+00:00',
        'total_price': 860,
        'created_at': DateTime.now().toIso8601String(),
        'motorcycles': null,
        'booking_branch': {'name': 'Velké Němčice', 'address': 'Boudky', 'city': 'Velké Němčice', 'gps_lat': 49.1, 'gps_lng': 16.7, 'type': 'samoobslužná'},
        'branch_id': 'br-vn',
        'gear_lines': _lines,
        'gear_per_day': 430,
      });
      expect(r.isGearOnly, isTrue);
      expect(r.isSelfService, isTrue);
      expect(r.motoName, cs.tr('gearBookingTitle'));
      expect(r.motoName, 'Výpůjčka výbavy');
      expect(r.branchLat, 49.1);
      expect(r.branchId, 'br-vn');
      expect(r.gearLines, hasLength(2));
      expect(r.gearPerDay, 430);
      expect(r.sosAllowed, isFalse);
    });

    test('moto beze změny: pobočka z motorky, booking_branch se ignoruje', () {
      final m = _moto('m');
      expect(m.isGearOnly, isFalse);
      expect(m.branchName, 'Mezná');
      expect(m.isSelfService, isFalse);
      expect(m.motoName, 'BMW R 1250 GS');
      expect(m.gearLines, isEmpty);
    });

    test('fromGearRpc: velikosti z lines, total, poukaz, pobočka, gear', () {
      final r = Reservation.fromGearRpc(_rpc());
      expect(r.bookingKind, 'gear');
      expect(r.isGearOnly, isTrue);
      expect(r.helmetSize, 'M');
      expect(r.jacketSize, 'L');
      expect(r.pantsSize, 'L');
      expect(r.glovesSize, 'M');
      expect(r.bootsSize, '43');
      expect(r.totalPrice, 760);
      expect(r.discountAmount, 100);
      expect(r.gearPerDay, 430);
      expect(r.branchType, 'samoobslužná');
      expect(r.branchId, 'br-vn');
      expect(r.branchLat, 49.0);
      expect(r.motoName, 'Výpůjčka výbavy');
      expect(r.pickupHm, '10:00');
      expect(r.dayCount, 2);
    });

    test('sosAllowed je u výbavy vždy false (i aktivní v termínu)', () {
      final r = Reservation.fromGearRpc(_rpc(status: 'active', from: 0, to: 1));
      expect(r.inRentalTerm, isTrue);
      expect(r.sosAllowed, isFalse);
    });

    test('souhrn: „Komplet bez bot (M, L, L, M) · Boty 43“, pobočka bez MotoGo24', () {
      final r = Reservation.fromGearRpc(_rpc());
      expect(gearSummary(r, cs), 'Komplet bez bot (M, L, L, M) · Boty 43');
      expect(gearSummary(r, cs, {'set_no_boots': 'Set without boots'}), startsWith('Set without boots (M, L, L, M)'));
      expect(gearBranchName(r.branchName), 'Velké Němčice');
      expect(gearItemSizes(r).keys.toList(), ['helmet', 'jacket', 'pants', 'gloves', 'boots']);
    });

    test('rozdělaná webová výpůjčka drží 4 h (motorka z appky 30 min)', () {
      final created = DateTime.now().subtract(const Duration(hours: 2)).toUtc().toIso8601String();
      final g = Reservation.fromGearRpc({..._rpc(status: 'pending', pay: 'unpaid'), 'created_at': created});
      expect(g.displayStatus, isNot(ResStatus.cancelled));
      expect(gearCanPay(g), isTrue);
      final old = Reservation.fromGearRpc({
        ..._rpc(status: 'pending', pay: 'unpaid'),
        'created_at': DateTime.now().subtract(const Duration(hours: 5)).toUtc().toIso8601String(),
      });
      expect(old.displayStatus, ResStatus.cancelled);
      expect(gearCanPay(old), isFalse);
    });

    test('historie: záznam gear_sizes je změna výbavy', () {
      final e = ModificationEntry.fromJson({'type': 'gear_sizes', 'source': 'web', 'at': DateTime.now().toIso8601String()});
      expect(e.hasGearChange, isTrue);
      expect(e.hasDateChange, isFalse);
    });
  });

  group('pravidla', () {
    test('checkOverlap: výpůjčka výbavy motorku neblokuje', () {
      final g = Reservation.fromGearRpc(_rpc(from: 5, to: 6));
      final start = DateTime.now().add(const Duration(days: 5));
      final end = DateTime.now().add(const Duration(days: 6));
      expect(
        BookingValidator.checkOverlap(userReservations: [g], startDate: start, endDate: end, isChildrensMoto: false),
        isNull,
      );
      expect(
        BookingValidator.checkOverlap(userReservations: [_moto('m', from: 5, to: 6)], startDate: start, endDate: end, isChildrensMoto: false),
        isNotNull,
      );
    });

    test('sloučení s RPC: dedupe podle id (tabulka vyhrává), řazení podle začátku', () {
      final g = Reservation.fromGearRpc(_rpc(from: 10, to: 11));
      final m = _moto('m', from: 3, to: 4);
      final merged = mergeGearBookings([m], [g]);
      expect(merged.map((r) => r.id), [g.id, m.id]);
      final tableGear = Reservation.fromGearRpc({..._rpc(from: 10, to: 11), 'total': 999});
      expect(mergeGearBookings([tableGear], [g]).single.totalPrice, 999);
      expect(mergeGearBookings([m], const []), [m]);
    });

    test('Domů S10 (hodnocení jízdy) výbavu přeskočí', () {
      final done = Reservation.fromGearRpc(_rpc(status: 'completed', from: -3, to: -2));
      final snap = deriveHomeState(reservations: [done]);
      expect(snap.ticket, HomeTicket.s0);
    });

    test('doklady: jen výbava → stačí OP / pas; s motorkou dál ŘP', () {
      const profile = DocsVerification();
      const gate = DocsGateChecklist(
        ok: false, idFront: true, idBack: true, passport: false, dlFront: false, dlBack: false,
        identityOk: true, licenseOk: false, hasDob: true, ageOk: true, expiryOk: false, groupsOk: false,
      );
      const s = DocsScreenStatus(profile, gate);
      final gear = Reservation.fromGearRpc(_rpc());
      expect(gearOnlyDocsScope([gear]), isTrue);
      expect(docsCompleteScoped(s, [gear]), isTrue);
      expect(docsCompleteScoped(s, [gear, _moto('m')]), isFalse);
      expect(docsCompleteScoped(null, [gear]), isTrue);
      final g = GearDocsScreenStatus(s);
      expect(g.isComplete, isTrue);
      expect(g.codesReady, isTrue);
      expect(gearIdOnlyGate(gate).ok, isTrue);
    });

    test('úpravy: velikosti / odebrání / storno jen u zaplacené reserved', () {
      final r = Reservation.fromGearRpc(_rpc());
      expect(gearSizesEditable(r), isTrue);
      expect(gearRemoveAllowed(r), isTrue);
      expect(gearCancelAllowed(r), isTrue);
      expect(gearDatesEditable(r), isTrue);
      final unpaid = Reservation.fromGearRpc(_rpc(status: 'pending', pay: 'unpaid'));
      expect(gearSizesEditable(unpaid), isFalse);
      expect(gearCancelAllowed(unpaid), isFalse);
      expect(gearDatesEditable(unpaid), isFalse);
      final active = Reservation.fromGearRpc(_rpc(status: 'active', from: 0, to: 1));
      expect(gearCancelAllowed(active), isFalse);
      expect(gearDatesEditable(active), isTrue);
      expect(gearEditErrorText(cs, 'out_of_stock'), cs.tr('gearErrStock'));
      expect(gearEditErrorText(cs, 'last_item'), cs.tr('gearErrLastItem'));
      expect(gearEditErrorText(cs, 'xyz'), cs.tr('gearErrGeneric'));
      expect(gearIsoDate(DateTime(2026, 3, 7)), '2026-03-07');
    });

    test('odkazy na web (resume / úprava termínu, jazyk mimo cs)', () {
      expect(gearWebResumeUri('abc', 'cs').toString(), 'https://motogo24.cz/pujceni-obleceni?resume=abc');
      expect(gearWebResumeUri('abc', 'de').toString(), 'https://motogo24.cz/pujceni-obleceni?resume=abc&lang=de');
      expect(gearWebEditUri('abc', 'cs').toString(),
          'https://motogo24.cz/upravit-rezervaci?edit_booking=abc&edit_tab=move');
    });

    test('texty: každý gear klíč DISPLAY v 8 jazycích, stejné {placeholdery}', () {
      const keys = [
        'gearBookingTitle', 'gearItems', 'gearPerDay', 'gearProtocolFirst', 'gearProcStep2', 'gearProcStep3',
        'gearProcReturn', 'gearStaffedPickup', 'gearAddItemContact', 'gearDocsIdOnly', 'gearSizesTitle',
        'gearRemoveSuccess', 'gearEditDatesWeb', 'gearEditDatesWebHint', 'gearPayNow', 'gearPayWeb',
      ];
      final ph = RegExp(r'\{[a-zA-Z]+\}');
      for (final k in keys) {
        final base = ph.allMatches(AppTranslations.of('cs').tr(k)).map((m) => m.group(0)).toSet();
        for (final l in ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk']) {
          final v = AppTranslations.of(l).tr(k);
          expect(v, isNot(k), reason: '$l $k');
          expect(ph.allMatches(v).map((m) => m.group(0)).toSet(), base, reason: '$l $k');
        }
      }
    });
  });
}
