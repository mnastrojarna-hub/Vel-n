import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_shadows.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../ride_card.dart' show rideDate, rideDuration, rideKm, rideSpeed;
import '../../ride_model.dart';
import 'ride_track_sketch_v2.dart';

/// v2 look of [RideCard] (board Zazitky `.rdc`): white card, 88 px track
/// sketch, tags (live / S MotoGo or Soukromá / Sdíleno), name, date, the
/// same facts as the old card (km, total time, riding time, Ø speed, stops,
/// photos, bike, description) and the SAME tap: `/ride/:id` with the
/// sibling ids for swiping (or the caller's [onTap]).
class RideCardV2 extends StatelessWidget {
  final UserRide ride;
  final VoidCallback? onTap;
  final List<String> siblingIds;

  const RideCardV2({super.key, required this.ride, this.onTap, this.siblingIds = const []});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final name = ride.name.isNotEmpty ? ride.name : tr.tr('rideUntitled');
    final mg = ride.bookingId != null;
    final avg = ride.avgSpeedKmh ?? ride.avgOverallKmh;
    final live = ride.isRecording;
    void open() {
      if (onTap != null) {
        onTap!();
        return;
      }
      // Sousedi pro listování swipem v detailu jízdy (jako stará karta).
      context.push('/ride/${ride.id}', extra: siblingIds);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        label: '$name, ${rideDate(ride.startedAt)}, ${rideKm(ride.distanceKm)}',
        child: MgPress(
          scale: 0.98,
          onTap: open,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: MgColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: live ? MgColors.sos : MgColors.line, width: live ? 1.5 : 1),
              boxShadow: MgShadows.card,
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              RideTrackSketch(ride: ride),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 4, runSpacing: 4, children: [
                    if (live) RideBadgeV2(kind: RideBadgeKind.live, label: tr.tr('rideRecording')),
                    RideBadgeV2(
                      kind: mg ? RideBadgeKind.motogo : RideBadgeKind.private,
                      label: tr.tr(mg ? 'v2RideFilterMg' : 'v2RideTagPriv'),
                    ),
                    if (ride.isPublic) RideBadgeV2(kind: RideBadgeKind.shared, label: tr.tr('rideShared')),
                  ]),
                  const SizedBox(height: 6),
                  Text(name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: MgType.title.copyWith(color: MgColors.ink)),
                  const SizedBox(height: 2),
                  Text(rideDate(ride.startedAt), style: MgType.tab(MgType.meta.copyWith(color: MgColors.meta))),
                  const SizedBox(height: 6),
                  Wrap(spacing: 10, runSpacing: 4, children: [
                    RideMetaV2(MgIcons.ruler, rideKm(ride.distanceKm), strong: true),
                    if (ride.totalMin > 0) RideMetaV2(MgIcons.clock, rideDuration(ride.totalMin)),
                    if (ride.movingSec > 0) RideMetaV2(MgIcons.ride, rideDuration(ride.movingMin)),
                    if (avg != null) RideMetaV2(MgIcons.speed, rideSpeed(avg)),
                    if (ride.stops.isNotEmpty) RideMetaV2(MgIcons.pin, '${ride.stops.length}'),
                    if (ride.photoCount > 0) RideMetaV2(MgIcons.camera, '${ride.photoCount}'),
                  ]),
                  if ((ride.motoName ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      const MgIcon(MgIcons.bike, size: 15, color: MgColors.link),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(ride.motoName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.link)),
                      ),
                    ]),
                  ],
                  if ((ride.description ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(ride.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: MgType.small.copyWith(color: MgColors.body2)),
                  ],
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
