import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_shadows.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_word_fit.dart';
import '../../ride_card.dart' show rideDuration, rideKm, rideSpeed;
import '../../ride_trip.dart';
import 'ride_card_v2.dart' show RideLiveBadgeV2;
import 'ride_phase_v2.dart';
import 'ride_track_sketch_v2.dart';

/// Display name of a trip in v2: the rider's name, else "Výpůjčka {moto}"
/// (a rental) or "Cesta {dates}" — like `rideTripDefaultName`, v2 keys.
String tripNameV2(AppTranslations tr, RideTrip trip) {
  final n = trip.name;
  if (n != null && n.trim().isNotEmpty) return n;
  final moto = trip.aggregate.motoName;
  if (trip.isRental && moto != null && moto.isNotEmpty) return tr.trArgs('v2RpTripRental', {'moto': moto});
  return tr.trArgs('v2RpTripDefault', {'dates': rideDateRange(trip.from, trip.to)});
}

/// One trip in the ride list (SPEC §9.2): a ride card with the CESTA · N
/// dní tag, the aggregate sketch, name, date range and the sums of all its
/// rides (rides · km · time in the saddle · Ø). Tap = trip detail.
class RideTripCardV2 extends StatelessWidget {
  final RideTrip trip;
  final VoidCallback onTap;
  const RideTripCardV2({super.key, required this.trip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final a = trip.aggregate;
    final name = tripNameV2(tr, trip);
    final days = trip.days;
    final range = rideDateRange(trip.from, trip.to);
    final rides = recRidesV2(tr, trip.rides.length);
    final mg = trip.rides.any((r) => r.bookingId != null);
    final live = trip.rides.where((r) => r.isRecording).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        label: '$name, ${tr.trArgs('v2RpTripCard', {'days': recDaysV2(tr, days)})}, $range, $rides, ${rideKm(a.distanceKm)}',
        excludeSemantics: true,
        child: MgPress(
          scale: 0.98,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: MgColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: live.isNotEmpty ? MgColors.sos : MgColors.ink, width: 1.5),
              boxShadow: MgShadows.card,
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              RideTrackSketch(ride: a),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 4, runSpacing: 4, children: [
                    RideBadgeV2(kind: RideBadgeKind.trip, label: tr.trArgs('v2RpTripCard', {'days': recDaysV2(tr, days)})),
                    if (live.isNotEmpty) RideLiveBadgeV2(rideId: live.first.id),
                    RideBadgeV2(
                      kind: mg ? RideBadgeKind.motogo : RideBadgeKind.private,
                      label: tr.tr(mg ? 'v2RideFilterMg' : 'v2RideTagPriv'),
                    ),
                    if (trip.isPublic) RideBadgeV2(kind: RideBadgeKind.shared, label: tr.tr('rideShared')),
                  ]),
                  const SizedBox(height: 6),
                  MgWordFit(
                    minScale: 0.8,
                    child: Text(name, maxLines: 3, overflow: TextOverflow.ellipsis, style: MgType.title.copyWith(color: MgColors.ink)),
                  ),
                  const SizedBox(height: 2),
                  Text(range, style: MgType.tab(MgType.meta.copyWith(color: MgColors.meta))),
                  const SizedBox(height: 6),
                  Wrap(spacing: 10, runSpacing: 4, children: [
                    RideMetaV2(MgIcons.ruler, rideKm(a.distanceKm), strong: true),
                    if (a.movingSec > 0) RideMetaV2(MgIcons.ride, tr.trArgs('v2RpChipRiding', {'time': rideDuration(a.movingMin)})),
                    if (a.avgSpeedKmh != null) RideMetaV2(MgIcons.speed, rideSpeed(a.avgSpeedKmh)),
                    RideMetaV2(MgIcons.list, rides),
                  ]),
                  if ((a.motoName ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      const MgIcon(MgIcons.bike, size: 15, color: MgColors.link),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(a.motoName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.link)),
                      ),
                    ]),
                  ],
                ]),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: MgIcon(MgIcons.chevronRight, size: 18, color: MgColors.lead),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
