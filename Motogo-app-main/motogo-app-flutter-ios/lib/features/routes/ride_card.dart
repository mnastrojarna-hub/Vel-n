import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/widgets/moto_fx.dart';
import 'ride_model.dart';
import 'ride_map.dart';

/// Karta jedné projeté jízdy v seznamu („Moje zážitky" i detail výpůjčky):
/// náhled stopy na mapě + název, datum, motorka, km / čas / zastávky a odznak
/// sdílení. Klepnutím se otevře detail jízdy.
class RideCard extends StatelessWidget {
  final UserRide ride;
  final VoidCallback? onTap;

  const RideCard({super.key, required this.ride, this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasMap = ride.mapPoints.length >= 2;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PressableScale(
        pressedScale: 0.98,
        onTap: onTap ?? () => context.push('/ride/${ride.id}'),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(MotoGoRadius.card),
            boxShadow: MotoGoShadows.cardSmall,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasMap)
                SizedBox(
                  height: 140,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: RideTrackMap(
                          track: ride.track,
                          points: ride.points,
                        ),
                      ),
                      if (ride.isRecording)
                        Positioned(
                          left: 10,
                          top: 10,
                          child: _badge('⏺ ${t(context).tr('rideRecording')}',
                              MotoGoColors.red, Colors.white),
                        ),
                      if (ride.isPublic)
                        Positioned(
                          right: 10,
                          top: 10,
                          child: _badge('🌍 ${t(context).tr('rideShared')}',
                              MotoGoColors.green, MotoGoColors.black),
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ride.name.isNotEmpty
                          ? ride.name
                          : t(context).tr('rideUntitled'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: MotoGoTypo.sizeXl,
                          fontWeight: MotoGoTypo.w900,
                          color: MotoGoColors.black,
                          decoration: TextDecoration.none),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        _meta(Icons.event, rideDate(ride.startedAt)),
                        _meta(Icons.straighten, rideKm(ride.distanceKm)),
                        if (ride.totalMin > 0)
                          _meta(Icons.schedule, rideDuration(ride.totalMin)),
                        if (ride.movingSec > 0)
                          _meta(Icons.motorcycle_outlined,
                              rideDuration(ride.movingMin)),
                        if ((ride.avgSpeedKmh ?? ride.avgOverallKmh) != null)
                          _meta(Icons.speed,
                              rideSpeed(ride.avgSpeedKmh ?? ride.avgOverallKmh)),
                        if (ride.stops.isNotEmpty)
                          _meta(Icons.place, '${ride.stops.length}'),
                        if (ride.photoCount > 0)
                          _meta(Icons.photo_camera, '${ride.photoCount}'),
                        if ((ride.motoName ?? '').isNotEmpty)
                          _meta(Icons.motorcycle, ride.motoName!),
                      ],
                    ),
                    if ((ride.description ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        ride.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: MotoGoTypo.sizeMd,
                            color: MotoGoColors.g500,
                            decoration: TextDecoration.none),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String label, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(MotoGoRadius.pill),
          boxShadow: MotoGoShadows.cardSmall,
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: MotoGoTypo.sizeSm,
              fontWeight: MotoGoTypo.w800,
              color: fg,
              decoration: TextDecoration.none),
        ),
      );

  Widget _meta(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: MotoGoColors.g400),
          const SizedBox(width: 4),
          Text(text,
              style: const TextStyle(
                  fontSize: MotoGoTypo.sizeMd,
                  fontWeight: MotoGoTypo.w700,
                  color: MotoGoColors.g600,
                  decoration: TextDecoration.none)),
        ],
      );
}

String rideDate(DateTime d) => '${d.day}. ${d.month}. ${d.year}';

/// Datum a čas jízdy („16. 9. 2026 8:23").
String rideDateTime(DateTime d) {
  final local = d.toLocal();
  final mm = local.minute.toString().padLeft(2, '0');
  return '${rideDate(local)} ${local.hour}:$mm';
}

String rideDuration(int min) {
  if (min < 60) return '$min min';
  final h = min ~/ 60;
  final m = min % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

/// Vzdálenost — pod 10 km s jedním desetinným místem, jinak celé km.
String rideKm(double km) => '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';

/// Rychlost v km/h; neznámá (stopa bez časů) se nevymýšlí.
String rideSpeed(double? kmh) =>
    kmh == null || kmh <= 0 ? '—' : '${kmh.toStringAsFixed(0)} km/h';
