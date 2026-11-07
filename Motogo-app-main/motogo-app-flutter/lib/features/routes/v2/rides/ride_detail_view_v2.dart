import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/states/mg_state_screen.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_shadows.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_word_fit.dart';
import '../../ride_map.dart';
import '../../ride_model.dart';
import '../../route_image.dart';
import 'ride_detail_parts_v2.dart';
import 'ride_stages_v2.dart';
import 'ride_trip_row_v2.dart';

/// v2 ride detail (board Zazitky "Detail jízdy"): dark header, the EXISTING
/// interactive track map (tap = new stop, tap a stop = edit), the one dark
/// stats card overlapping it (SPEC §9.3), then light: the trip row (part of
/// a trip / add to a trip — reads the ride list itself), sharing switch,
/// Etapy (multi-day ride), stops with notes and photos. A dumb view for
/// the ride itself — every callback is the old State's method.
class RideDetailViewV2 extends StatelessWidget {
  final UserRide ride;
  final bool busy;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final ValueChanged<LatLng> onMapTap;
  final ValueChanged<int> onPointTap;
  final ValueChanged<RidePoint> onEditPoint;
  final ValueChanged<bool> onVisibility;

  const RideDetailViewV2({
    super.key,
    required this.ride,
    required this.busy,
    required this.onBack,
    required this.onEdit,
    required this.onShare,
    required this.onDelete,
    required this.onMapTap,
    required this.onPointTap,
    required this.onEditPoint,
    required this.onVisibility,
  });

  static const double _mapH = 260;

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: MgColors.canvas,
      body: Column(children: [
        RideDetailHeaderV2(ride: ride, onBack: onBack, onEdit: onEdit, onShare: onShare, onDelete: onDelete),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 32 + bottom),
            children: [
              Stack(children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: _mapH,
                  child: Container(
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: MgShadows.card),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(children: [
                      Positioned.fill(
                        child: RideTrackMap(
                          track: ride.track,
                          segments: ride.segments,
                          points: ride.points,
                          interactive: true,
                          onMapTap: onMapTap,
                          onPointTap: onPointTap,
                        ),
                      ),
                      Positioned(left: 10, top: 10, right: 10, child: _MapHint(text: tr.tr('v2RideMapHint'))),
                    ]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: _mapH - 24),
                  child: MgReveal(sessionKey: 'ride-stats-${ride.id}', child: RideStatsCardV2(ride: ride)),
                ),
              ]),
              const SizedBox(height: 16),
              RideTripRowV2(ride: ride),
              const SizedBox(height: 8),
              RideVisibilityCardV2(isPublic: ride.isPublic, busy: busy, onChanged: onVisibility),
              if (ride.stages.length >= 2) ...[
                const SizedBox(height: 24),
                RideStagesV2(stages: ride.stages),
              ],
              const SizedBox(height: 24),
              Row(children: [
                const MgIcon(MgIcons.pin, size: 20, color: MgColors.routeGreen),
                const SizedBox(width: 8),
                Expanded(
                  // r1: „Stopps und Sehenswürdigkeiten" celé, slovo se nedělí.
                  child: Semantics(
                    header: true,
                    child: MgWordFit(minScale: 0.75, child: Text(tr.tr('rideStops'), style: MgType.section.copyWith(color: MgColors.ink))),
                  ),
                ),
                if (ride.points.isNotEmpty)
                  Text('${ride.points.length}', style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.meta))),
              ]),
              const SizedBox(height: 4),
              Text(tr.tr('rideStopsHint'), style: MgType.small.copyWith(color: MgColors.meta)),
              const SizedBox(height: 12),
              for (var i = 0; i < ride.points.length; i++)
                RidePointCardV2(point: ride.points[i], number: i, onTap: () => onEditPoint(ride.points[i])),
            ],
          ),
        ),
      ]),
    );
  }
}

class _MapHint extends StatelessWidget {
  final String text;
  const _MapHint({required this.text});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topLeft,
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: MgColors.nightA(0.80),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: MgColors.white(0.20)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const MgIcon(MgIcons.finger, size: 14, color: MgColors.neon),
              const SizedBox(width: 6),
              Flexible(child: MgWordFit(minScale: 0.8, child: Text(text, style: MgType.meta.copyWith(color: MgColors.onDark)))),
            ]),
          ),
        ),
      );
}

/// A stop / start / finish of the ride (board `.ptc`): marker, name (or
/// Start / Cíl / Zastávka), note, photos; tap = the existing point editor.
class RidePointCardV2 extends StatelessWidget {
  final RidePoint point;
  final int number;
  final VoidCallback onTap;
  const RidePointCardV2({super.key, required this.point, required this.number, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final p = point;
    final title = p.name.isNotEmpty ? p.name : tr.tr(p.isStart ? 'rideStart' : p.isEnd ? 'rideEnd' : 'rideStop');
    final (bg, fg, icon) = p.isStart
        ? (MgColors.neon, MgColors.onNeon, MgIcons.flag)
        : p.isEnd
            ? (MgColors.ink, MgColors.neon, MgIcons.trophy)
            : (MgColors.panel, MgColors.neon, null);
    Widget broken(BuildContext _) => const ColoredBox(
          color: MgColors.well,
          child: Center(child: MgIcon(MgIcons.image, size: 18, color: MgColors.meta)),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        label: '$title, ${tr.tr('ridePointEdit')}',
        child: MgPress(
          scale: 0.98,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: MgColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: MgColors.line),
              boxShadow: MgShadows.card,
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                  child: Center(
                    child: icon != null
                        ? MgIcon(icon, size: 15, color: fg)
                        : Text('$number', style: MgType.tab(MgType.micro.copyWith(fontWeight: FontWeight.w800, color: fg))),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MgWordFit(
                    minScale: 0.8,
                    child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: MgType.title.copyWith(color: MgColors.ink)),
                  ),
                ),
                const MgIcon(MgIcons.edit, size: 18, color: MgColors.meta),
              ]),
              if ((p.note ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 38),
                  child: Text(p.note!, style: MgType.small.copyWith(color: MgColors.body2)),
                ),
              ],
              if (p.photos.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 84,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(left: 38),
                    itemCount: p.photos.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (c, i) => ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 110,
                        height: 84,
                        child: RouteImage(
                          url: p.photos[i],
                          targetWidth: 320,
                          placeholder: (_) => const ColoredBox(color: MgColors.well),
                          error: broken,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// "Jízda nenalezena" (T1): what happened + the old way out (back to Moje
/// zážitky), back disc in the corner.
class RideMissingV2 extends StatelessWidget {
  final VoidCallback onBack;
  const RideMissingV2({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return MgStateScreen(
      tone: MgTone.info,
      icon: MgIcons.bike,
      title: tr.tr('rideNotFound'),
      why: tr.tr('v2RideMissingWhy'),
      support: false,
      onClose: onBack,
      closeIsBack: true,
      primary: MgStateAction(tr.tr('v2RideBackToMine'), onBack),
    );
  }
}
