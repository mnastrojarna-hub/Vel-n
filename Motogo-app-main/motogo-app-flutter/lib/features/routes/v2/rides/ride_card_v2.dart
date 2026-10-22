import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_shadows.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_word_fit.dart';
import '../../ride_card.dart' show rideDuration, rideKm, rideSpeed;
import '../../ride_model.dart';
import '../../ride_recorder.dart';
import '../../ride_trip.dart' show rideDateRange;
import 'ride_phase_v2.dart';
import 'ride_track_sketch_v2.dart';

/// v2 look of [RideCard] (board Zazitky `.rdc`, SPEC §9.3): white card,
/// 88 px track sketch, tags (live by phase — Nahrávám / Pozastaveno —, S
/// MotoGo or Soukromá, Sdíleno, "3 dny"), name, date or range, km · time in
/// the saddle (not the total incl. nights) · Ø · stops · photos, bike,
/// description and the SAME tap: `/ride/:id` with the sibling ids for
/// swiping (or the caller's [onTap]).
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
    final range = rideDateRange(ride.startedAt, ride.endedAt ?? ride.lastFixAt ?? ride.startedAt);
    final days = ride.days;
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
        label: '$name, $range, ${rideKm(ride.distanceKm)}${days >= 2 ? ', ${recDaysV2(tr, days)}' : ''}',
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
                    if (live) RideLiveBadgeV2(rideId: ride.id),
                    RideBadgeV2(
                      kind: mg ? RideBadgeKind.motogo : RideBadgeKind.private,
                      label: tr.tr(mg ? 'v2RideFilterMg' : 'v2RideTagPriv'),
                    ),
                    if (ride.isPublic) RideBadgeV2(kind: RideBadgeKind.shared, label: tr.tr('rideShared')),
                    if (days >= 2) RideBadgeV2(kind: RideBadgeKind.days, label: recDaysV2(tr, days)),
                  ]),
                  const SizedBox(height: 6),
                  // Celý název (až 3 řádky), slovo se nikdy nerozdělí (de „Aufgezeichnete").
                  MgWordFit(
                    minScale: 0.8,
                    child: Text(name,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: MgType.title.copyWith(color: MgColors.ink)),
                  ),
                  const SizedBox(height: 2),
                  Text(range, style: MgType.tab(MgType.meta.copyWith(color: MgColors.meta))),
                  const SizedBox(height: 6),
                  Wrap(spacing: 10, runSpacing: 4, children: [
                    RideMetaV2(MgIcons.ruler, rideKm(ride.distanceKm), strong: true),
                    // Čas v sedle — ne celkový čas (u vícedenní cesty i s nocemi).
                    if (ride.movingSec > 0)
                      RideMetaV2(MgIcons.ride, tr.trArgs('v2RpChipRiding', {'time': rideDuration(ride.movingMin)}))
                    else if (ride.totalMin > 0)
                      RideMetaV2(MgIcons.clock, rideDuration(ride.totalMin)),
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

/// Recording badge of the ride being recorded right now, by phase:
/// "● Nahrávám" (red) while riding, "❚❚ Pozastaveno" / "Čeká na rozjezd"
/// (neutral) otherwise. Falls back to "Nahrávám" when the recorder holds
/// another ride (server flag only).
class RideLiveBadgeV2 extends ConsumerWidget {
  final String rideId;
  final bool dark;
  const RideLiveBadgeV2({super.key, required this.rideId, this.dark = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final rec = ref.watch(rideRecorderProvider);
    if (!rec.recording || rec.rideId != rideId) {
      return RideBadgeV2(kind: RideBadgeKind.live, label: tr.tr('rideRecording'), dark: dark);
    }
    final ph = RecPhaseV2.of(tr, rec);
    final riding = ph.tone == RecToneV2.rec || ph.tone == RecToneV2.warn;
    return RideBadgeV2(kind: riding ? RideBadgeKind.live : RideBadgeKind.paused, label: ph.chip, dark: dark);
  }
}
