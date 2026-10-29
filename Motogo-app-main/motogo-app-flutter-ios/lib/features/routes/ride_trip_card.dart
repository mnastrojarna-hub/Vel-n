import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/theme.dart';
import '../../core/widgets/moto_fx.dart';
import 'ride_card.dart';
import 'ride_live_stats.dart';
import 'ride_map.dart';
import 'ride_merge_screen.dart';
import 'ride_model.dart';
import 'ride_rec_controls.dart' show rideRecTone;
import 'ride_rec_phase.dart' show rideChipKey;
import 'ride_recorder.dart';
import 'ride_trip.dart';
import 'ride_trip_detail_screen.dart';

/// Seznam „Mých jízd" seskupený do cest (SPEC §8.2, §9.1): samostatná jízda
/// = [RideCard], cesta (sloučené jízdy / jízdy jedné výpůjčky) = [RideTripCard].
/// [ids] = pořadí pro listování swipem v detailu jízdy.
List<Widget> rideListWidgets(List<UserRide> rides, {List<RideListItem>? items}) {
  final ids = [for (final r in rides) r.id];
  return [
    for (final i in items ?? groupRides(rides))
      switch (i) {
        RideListItemRide(:final ride) => RideCard(ride: ride, siblingIds: ids),
        RideListItemTrip(:final trip) => RideTripCard(trip: trip),
      },
  ];
}

/// Otevře detail cesty (podle kterékoli její jízdy).
Future<void> openRideTrip(BuildContext context, RideTrip trip) => Navigator.of(context)
    .push(MaterialPageRoute<void>(builder: (_) => RideTripDetailScreen(rideId: trip.leader.id)));

/// Otevře výběr jízd ke sloučení ([preselectRideId] = předvybraná jízda).
Future<void> openRideMerge(BuildContext context, {String? preselectRideId}) => Navigator.of(context)
    .push(MaterialPageRoute<void>(builder: (_) => RideMergeScreen(preselectRideId: preselectRideId)));

/// Karta cesty: náhled celé trasy, název, rozsah dat a součty.
class RideTripCard extends ConsumerWidget {
  const RideTripCard({super.key, required this.trip});

  final RideTrip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    // Cesta s právě nahrávanou jízdou: štítek podle fáze záznamu (stejně
    // jako karta jízdy) — „Auto-pauza" / „Pozastaveno", ne pořád „Nahrávám".
    final rec = ref.watch(rideRecorderProvider);
    final mine = rec.recording && trip.rides.any((r) => r.id == rec.rideId);
    final tone = mine ? rideRecTone(rec) : null;
    final a = trip.aggregate;
    final name = rideTripDefaultName(trip, tr);
    final days = trip.days;
    final line = [
      rideRidesLabel(trip.rides.length, tr),
      if (days >= 2) rideDaysLabel(days, tr),
      rideKm(a.distanceKm),
      if (a.movingSec > 0) tr.trArgs('rpSaddle', {'time': rideDuration(a.movingMin)}),
    ].join(' · ');
    final hasMap = a.mapPoints.length >= 2;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        button: true,
        label: '${tr.tr('rpTripChip')}: $name, ${rideDateRange(trip.from, trip.to)}, $line',
        excludeSemantics: true,
        child: PressableScale(
          pressedScale: 0.98,
          onTap: () => openRideTrip(context, trip),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(MotoGoRadius.card),
              border: Border.all(color: MotoGoColors.greenDark.withValues(alpha: 0.5), width: 1.4),
              boxShadow: MotoGoShadows.cardSmall,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (hasMap)
                SizedBox(
                  height: 140,
                  child: RideTrackMap(track: a.track, segments: a.segments, points: a.points),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    _chip('${trip.isRental ? '🏍️' : '🧳'} ${tr.tr('rpTripChip')}', MotoGoColors.greenPale,
                        MotoGoColors.greenDarker),
                    if (tone != null)
                      _chip('${tone.glyph} ${tr.tr(rideChipKey(rec)!)}', tone.fg, Colors.white)
                    else if (trip.isRecording)
                      _chip('⏺ ${tr.tr('rideRecording')}', MotoGoColors.red, Colors.white),
                    if (trip.isPublic) _chip('🌍 ${tr.tr('rideShared')}', MotoGoColors.green, MotoGoColors.black),
                  ]),
                  const SizedBox(height: 6),
                  Text(name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: MotoGoTypo.sizeXl,
                          fontWeight: MotoGoTypo.w900,
                          color: MotoGoColors.black,
                          decoration: TextDecoration.none)),
                  const SizedBox(height: 4),
                  Text('📅 ${rideDateRange(trip.from, trip.to)}', style: _meta),
                  const SizedBox(height: 2),
                  Text(line, style: _meta),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  static const _meta = TextStyle(
      fontSize: MotoGoTypo.sizeMd,
      fontWeight: MotoGoTypo.w700,
      color: MotoGoColors.g600,
      height: 1.35,
      decoration: TextDecoration.none);

  Widget _chip(String label, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(MotoGoRadius.pill)),
        child: Text(label,
            style: TextStyle(
                fontSize: MotoGoTypo.sizeSm, fontWeight: MotoGoTypo.w800, color: fg, decoration: TextDecoration.none)),
      );
}

/// Řádek „🔗 Sloučit jízdy" — jen když to server umí a je co slučovat.
class RideMergeRow extends StatelessWidget {
  const RideMergeRow({super.key});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        button: true,
        label: tr.tr('rpMerge'),
        excludeSemantics: true,
        child: PressableScale(
          pressedScale: 0.98,
          onTap: () => openRideMerge(context),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(MotoGoRadius.card),
              boxShadow: MotoGoShadows.cardSmall,
            ),
            child: Row(children: [
              const Text('🔗', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(tr.tr('rpMerge'),
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
    );
  }
}
