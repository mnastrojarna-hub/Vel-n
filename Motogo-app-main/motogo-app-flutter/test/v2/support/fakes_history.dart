// Fixtures of "Historie rezervace" (ResModificationHistory / ResHistoryV2):
// a booking shortened by a day with one customer edit (dates, bike, time,
// helmet), and a cancelled booking ended by SOS with an incident.
import 'package:motogo_app/features/reservations/reservation_models.dart';
import 'package:motogo_app/features/reservations/reservation_provider.dart';

import 'fakes_reservations.dart' show rday;

String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

/// Shortened from 5 to 4 days (start +2, end +1) by one customer edit.
Reservation histModsRes() => Reservation(
      id: 'h1aaaaaaa-1111-2222-3333-444455556666',
      motoName: 'Husqvarna 701 SM',
      status: 'reserved',
      paymentStatus: 'paid',
      startDate: rday(6),
      endDate: rday(9),
      totalPrice: 12027,
      createdAt: rday(-10).add(const Duration(hours: 9, minutes: 12)),
      confirmedAt: rday(-10).add(const Duration(hours: 9, minutes: 14)),
      originalStartDate: rday(4),
      originalEndDate: rday(8),
      modificationHistory: [
        ModificationEntry(
          at: rday(-3).add(const Duration(hours: 14, minutes: 36)),
          fromStart: _iso(rday(4)),
          fromEnd: _iso(rday(8)),
          toStart: _iso(rday(6)),
          toEnd: _iso(rday(9)),
          fromMoto: 'BMW R 1200 GS',
          toMoto: 'Husqvarna 701 SM',
          fromPickupTime: '09:00',
          toPickupTime: '12:00',
          gearChanges: const {
            'helmet': {'from': 'M', 'to': 'L'},
          },
        ),
        ModificationEntry(
          at: rday(-2).add(const Duration(hours: 8, minutes: 5)),
          fromStart: _iso(rday(6)),
          fromEnd: _iso(rday(9)),
          toStart: _iso(rday(6)),
          toEnd: _iso(rday(9)),
          fromPickupMethod: 'store',
          toPickupMethod: 'delivery',
          toPickupAddress: 'Masarykova 12, Brno',
          fromPickupAddress: '',
          extrasChanged: true,
          source: 'admin',
        ),
      ],
    );

/// Cancelled after an SOS (ended by SOS, replacement, one incident).
Reservation histCancelSosRes() => Reservation(
      id: 'h2aaaaaaa-1111-2222-3333-444455556666',
      motoName: 'BMW R 1200 GS Adventure',
      status: 'cancelled',
      paymentStatus: 'refunded',
      startDate: rday(-2),
      endDate: rday(2),
      totalPrice: 12027,
      createdAt: rday(-20),
      confirmedAt: rday(-20).add(const Duration(minutes: 3)),
      cancelledAt: rday(-1).add(const Duration(hours: 16, minutes: 2)),
      cancelledBySource: 'admin',
      cancellationReason: 'Nehoda – motorka nepojízdná',
      stornoFee: 0,
      refundAmount: 4810,
      endedBySos: true,
      sosReplacement: true,
      sosIncidentId: 'inc-0000-1111-2222-ab12cd34',
    );

List<SosIncident> histIncidents() => [
      SosIncident(
        id: 'inc-0000-1111-2222-ab12cd34',
        type: 'accident_minor',
        title: 'Pád v zatáčce, poškozená páčka',
        status: 'resolved',
        createdAt: rday(-1).add(const Duration(hours: 11, minutes: 20)),
        resolvedAt: rday(-1).add(const Duration(hours: 15, minutes: 45)),
      ),
    ];
