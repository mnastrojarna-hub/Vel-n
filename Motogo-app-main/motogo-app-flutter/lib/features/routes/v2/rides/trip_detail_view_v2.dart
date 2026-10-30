import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/states/mg_state_banner.dart';
import '../../../../core/v2/states/mg_tone.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_shadows.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/v2/widgets/mg_word_fit.dart';
import '../../ride_map.dart';
import '../../ride_model.dart';
import '../../ride_trip.dart';
import '../../ride_trip_api.dart' show RideTripOpResult;
import 'ride_card_v2.dart';
import 'ride_detail_parts_v2.dart';
import 'ride_phase_v2.dart';
import 'ride_stages_v2.dart';
import 'ride_track_sketch_v2.dart';
import 'trip_actions_v2.dart' show tripErrorKeyV2;

/// v2 trip detail (SPEC §9.2, composed of the ride-detail parts): dark
/// header (name — tap = rename, share, delete; range · bike; CESTA · N dní
/// / S MotoGo / Sdíleno), the map of all its rides with the stats card of
/// the sums (time in the saddle, breaks, days, rides…), sharing of the
/// whole trip, Etapy, the rides of the trip and "Rozdělit cestu". A dumb
/// view: every action is a callback ([TripDetailScreenV2] in v2, or the
/// old trip screen's seam).
class TripDetailViewV2 extends StatelessWidget {
  final RideTrip trip;
  final String name;
  final bool busy;
  final RideTripOpResult? error;
  final VoidCallback onBack;
  final VoidCallback onRename;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final VoidCallback onSplit;
  final ValueChanged<bool> onVisibility;

  /// Tap on a ride of the trip (null = the ride card's own `/ride/:id`).
  final ValueChanged<UserRide>? onOpenRide;

  const TripDetailViewV2({
    super.key,
    required this.trip,
    required this.name,
    required this.busy,
    this.error,
    required this.onBack,
    required this.onRename,
    required this.onShare,
    required this.onDelete,
    required this.onSplit,
    required this.onVisibility,
    this.onOpenRide,
  });

  static const double _mapH = 240;

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final a = trip.aggregate;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final range = rideDateRange(trip.from, trip.to);
    final mg = trip.rides.any((r) => r.bookingId != null);
    final live = trip.rides.where((r) => r.isRecording).toList();
    final ids = [for (final r in trip.rides) r.id];
    return Scaffold(
      backgroundColor: MgColors.canvas,
      body: Column(children: [
        RideHeaderShellV2(
          title: name,
          sub: [range, if ((a.motoName ?? '').isNotEmpty) a.motoName!].join(' · '),
          onBack: onBack,
          onEdit: onRename,
          onShare: onShare,
          onDelete: onDelete,
          shareLabel: tr.tr('v2RpTripShare'),
          deleteLabel: tr.tr('v2RpTripDelete'),
          badges: [
            RideBadgeV2(kind: RideBadgeKind.trip, label: tr.trArgs('v2RpTripCard', {'days': recDaysV2(tr, trip.days)}), dark: true),
            if (live.isNotEmpty) RideLiveBadgeV2(rideId: live.first.id, dark: true),
            RideBadgeV2(kind: mg ? RideBadgeKind.motogo : RideBadgeKind.private, label: tr.tr(mg ? 'v2RideFilterMg' : 'v2RideTagPriv'), dark: true),
            if (trip.isPublic) RideBadgeV2(kind: RideBadgeKind.shared, label: tr.tr('rideShared'), dark: true),
          ],
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 32 + bottom),
            children: [
              if (error != null) ...[
                MgStateBanner(tone: MgTone.err, icon: MgIcons.alert, title: tr.tr('v2RpTripFailTitle'), text: tr.tr(tripErrorKeyV2(error!))),
                const SizedBox(height: 12),
              ],
              Stack(children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: _mapH,
                  child: Container(
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: MgShadows.card),
                    clipBehavior: Clip.antiAlias,
                    child: RideTrackMap(track: a.track, segments: a.segments, points: a.points),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: _mapH - 24),
                  child: MgReveal(
                    sessionKey: 'trip-stats-${trip.leader.id}',
                    child: RideStatsCardV2(ride: a, days: trip.days, rides: trip.rides.length),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              RideVisibilityCardV2(
                isPublic: trip.isPublic,
                busy: busy,
                onChanged: onVisibility,
                title: tr.tr('v2RpTripVisibility'),
                onText: tr.tr('v2RpTripVisOn'),
                offText: tr.tr('v2RpTripVisOff'),
              ),
              if (a.stages.length >= 2) ...[
                const SizedBox(height: 24),
                RideStagesV2(stages: a.stages),
              ],
              const SizedBox(height: 24),
              Row(children: [
                const MgIcon(MgIcons.list, size: 20, color: MgColors.routeGreen),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: MgWordFit(minScale: 0.75, child: Text(tr.tr('v2RpTripMembers'), style: MgType.section.copyWith(color: MgColors.ink))),
                  ),
                ),
                Text('${trip.rides.length}', style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.meta))),
              ]),
              const SizedBox(height: 12),
              // Nejnovější nahoře, jako v seznamu jízd.
              for (final r in trip.rides.reversed)
                RideCardV2(ride: r, siblingIds: ids, onTap: onOpenRide == null ? null : () => onOpenRide!(r)),
              const SizedBox(height: 8),
              MgBtnGhostLight(label: tr.tr('v2RpTripSplit'), icon: MgIcons.cut, onTap: busy ? null : onSplit),
              const SizedBox(height: 4),
              Text(tr.tr('v2RpTripSplitHint'), textAlign: TextAlign.center, style: MgType.small.copyWith(color: MgColors.meta)),
            ],
          ),
        ),
      ]),
    );
  }
}
