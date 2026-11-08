import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../home/v2/home_sketch.dart';
import '../my_experiences_provider.dart' show SavedRoute;
import '../road_line.dart';
import '../routes_map_provider.dart' show routeRoadLineProvider;
import '../routes_model.dart';
import 'rides/ride_track_sketch_v2.dart';

/// Náhled trasy (karta v seznamu, Domů) VŽDY po silnici — pokyn majitele
/// 2026-11-08: „všechny trasy se všude zobrazovaly přepočítané po silnici a
/// ne jen přímky mezi body“. Odlehčený seznam tras geometrii neposílá, takže
/// se čára vezme stejně jako na mapě tras (`routeRoadLineProvider`: uložená
/// geometrie z Velína, jinak živý routing). Dokud čára není (nebo routing
/// selže), kreslí se jen ikona dlaždice — nikdy rovné spojnice zastávek.
class RouteRoadSketchV2 extends ConsumerWidget {
  final RouteItem route;
  final double width;
  final double height;
  final bool tile;
  final double stroke;
  const RouteRoadSketchV2({
    super.key,
    required this.route,
    required this.width,
    required this.height,
    this.tile = true,
    this.stroke = 2.2,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final line = routeRoadLine(ref, route);
    // Bez dlaždice (čára přes fotku) se bez čáry nekreslí nic — ikona trasy
    // by přes fotku jen překážela.
    if (line.length < 2 && !tile) return SizedBox(width: width, height: height);
    return HomeSketch(points: line, width: width, height: height, tile: tile, stroke: stroke);
  }
}

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
