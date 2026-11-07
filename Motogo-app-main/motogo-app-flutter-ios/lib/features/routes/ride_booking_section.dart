import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import 'ride_card.dart';
import 'ride_live_stats.dart' show rideRidesLabel;
import 'ride_provider.dart';
import 'ride_trip.dart';
import 'ride_trip_card.dart';

/// Projeté jízdy k jedné výpůjčce — zobrazuje se v detailu rezervace
/// (historie zákazníka). Jízdy vznikly automaticky během půjčení, když měl
/// zákazník povolenou polohu. Když žádná není, sekce se vůbec nevykreslí.
/// Víc jízd = součet za výpůjčku nahoře; jízdy jedné cesty (výpůjčka
/// rozdělená nocí u starší verze appky, sloučené jízdy) = karta cesty
/// a pod ní její jízdy.
class BookingRidesSection extends ConsumerWidget {
  final String bookingId;

  const BookingRidesSection({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rides = ref.watch(bookingRidesProvider(bookingId)).valueOrNull ?? const [];
    if (rides.isEmpty) return const SizedBox.shrink();
    final tr = t(context);
    final ids = [for (final x in rides) x.id];
    final km = rides.fold<double>(0, (s, r) => s + r.distanceKm);
    final moving = rides.fold<int>(0, (s, r) => s + r.movingSec);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '🏍️ ${tr.tr('rideBookingSection')}',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: MotoGoColors.g400,
              letterSpacing: 0.5,
            ),
          ),
        ),
        if (rides.length >= 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              tr.trArgs('rpBookingTotal', {
                'rides': rideRidesLabel(rides.length, tr),
                'km': rideKm(km),
                'time': rideDuration((moving / 60).round()),
              }),
              style: const TextStyle(
                fontSize: MotoGoTypo.sizeBase,
                fontWeight: MotoGoTypo.w800,
                color: MotoGoColors.g600,
                height: 1.35,
              ),
            ),
          ),
        for (final i in groupRides(rides))
          ...switch (i) {
            RideListItemRide(:final ride) => [RideCard(ride: ride, siblingIds: ids)],
            RideListItemTrip(:final trip) => [
                RideTripCard(trip: trip),
                for (final r in trip.rides.reversed) RideCard(ride: r, siblingIds: ids),
              ],
          },
      ],
    );
  }
}
