import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/theme.dart';
import 'ride_model.dart';
import 'ride_provider.dart';
import 'ride_trip.dart';
import 'ride_trip_api.dart';
import 'ride_trip_card.dart';
import 'ride_trip_ui.dart';

/// Najde cestu (≥ 2 jízdy), do které jízda [rideId] patří; null = samostatná.
RideTrip? rideTripOf(List<UserRide> rides, String rideId) {
  for (final i in groupRides(rides)) {
    if (i is RideListItemTrip && i.trip.rides.any((r) => r.id == rideId)) return i.trip;
  }
  return null;
}

/// Řádek „Cesta" v detailu jízdy (SPEC §9.1): člen cesty → „🧳 Součást cesty
/// {název} ›" + „Vyjmout z cesty" (se „Zpět"); samostatná jízda → „Přidat do
/// cesty…" (jen když to server umí). Jinak se nevykreslí nic.
class RideTripRow extends ConsumerStatefulWidget {
  const RideTripRow({super.key, required this.ride});

  final UserRide ride;

  @override
  ConsumerState<RideTripRow> createState() => _RideTripRowState();
}

class _RideTripRowState extends ConsumerState<RideTripRow> {
  bool _busy = false;

  Future<void> _remove() async {
    if (_busy) return;
    setState(() => _busy = true);
    final r = widget.ride;
    final op = await rideTripApply(ref, rideTripRemovePlan(r), bookingIds: [r.bookingId]);
    if (!mounted) return;
    setState(() => _busy = false);
    rideTripSnack(context, op, 'rpTripRemoved', bookingIds: [r.bookingId]);
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final rides = ref.watch(myRidesProvider).valueOrNull ?? const <UserRide>[];
    final trip = rideTripOf(rides, widget.ride.id);
    if (trip == null) {
      if (!rideTripsAvailable(rides)) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(44, 44), foregroundColor: MotoGoColors.greenDarker),
            onPressed: () => openRideMerge(context, preselectRideId: widget.ride.id),
            icon: const Icon(Icons.add_link, size: 20),
            label: Text(tr.tr('rpTripAddTo'),
                style: const TextStyle(fontSize: MotoGoTypo.sizeLg, fontWeight: MotoGoTypo.w800)),
          ),
        ),
      );
    }
    final name = rideTripDefaultName(trip, tr);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoRadius.card),
        boxShadow: MotoGoShadows.cardSmall,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(
          button: true,
          label: tr.trArgs('rpTripPartOf', {'name': name}),
          excludeSemantics: true,
          child: InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(MotoGoRadius.card)),
            onTap: () => openRideTrip(context, trip),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 4),
                child: Row(children: [
                  Text(trip.isRental ? '🏍️' : '🧳', style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(tr.trArgs('rpTripPartOf', {'name': name}),
                        style: const TextStyle(
                            fontSize: MotoGoTypo.sizeLg,
                            fontWeight: MotoGoTypo.w800,
                            color: MotoGoColors.black,
                            decoration: TextDecoration.none)),
                  ),
                  const Icon(Icons.chevron_right, color: MotoGoColors.g400),
                ]),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 4),
          child: TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(44, 44), foregroundColor: MotoGoColors.g600),
            onPressed: _busy ? null : _remove,
            icon: const Icon(Icons.link_off, size: 18),
            label: Text(tr.tr('rpTripRemove'),
                style: const TextStyle(fontSize: MotoGoTypo.sizeBase, fontWeight: MotoGoTypo.w700)),
          ),
        ),
      ]),
    );
  }
}
