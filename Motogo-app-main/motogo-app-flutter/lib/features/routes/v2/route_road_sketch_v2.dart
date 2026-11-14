import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../my_experiences_provider.dart' show SavedRoute;
import '../road_line.dart';
import '../routes_map_provider.dart' show routeRoadLineProvider;
import '../routes_model.dart';
import 'rides/ride_track_sketch_v2.dart';

/// Čára trasy z katalogu po silnici (prázdná, dokud není spočítaná).
List<LatLng> routeRoadLine(WidgetRef ref, RouteItem route) {
  if (route.geometry.length >= 2) return route.geometry;
  if (route.id.isEmpty) return const <LatLng>[];
  return ref.watch(routeRoadLineProvider(route.id)).valueOrNull ?? const <LatLng>[];
}

/// Uložená vlastní trasa (Moje zážitky) — po silnici v profilu, který si
/// jezdec zvolil v editoru.
class SavedRouteRoadSketchV2 extends ConsumerWidget {
  final SavedRoute route;
  final double size;
  const SavedRouteRoadSketchV2({super.key, required this.route, this.size = 56});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final line = route.waypoints.length < 2
        ? const <LatLng>[]
        : ref.watch(roadLineProvider(RoadLineKey(route.waypoints, profile: route.profile))).valueOrNull ??
            const <LatLng>[];
    return RideTrackSketch.line(line, size: size);
  }
}
