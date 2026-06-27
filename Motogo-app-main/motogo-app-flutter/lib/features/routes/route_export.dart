import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

/// Přenos trasy se zastávkami do externí navigace — Mapy.com / Google Maps /
/// Apple Maps. Body = uspořádaný seznam (start pobočka → waypointy → u okruhu zpět).
class RouteExport {
  RouteExport._();

  static String _ll(LatLng p) =>
      '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}';

  /// Mapy.com — plánovač trasy přes všechny body (otevře appku Mapy / web).
  /// Mapy používají pořadí lon,lat (x,y).
  static Uri mapy(List<LatLng> points) {
    final wp = points
        .map((p) => '${p.longitude.toStringAsFixed(6)},${p.latitude.toStringAsFixed(6)}')
        .join(';');
    return Uri.parse('https://mapy.com/fnc/v1/route?mapset=outdoor&routeType=car_fast&waypoints=$wp');
  }

  /// Google Maps directions URL s mezizastávkami.
  static Uri googleMaps(List<LatLng> points) {
    final origin = points.first;
    final dest = points.last;
    final waypoints = points.length > 2 ? points.sublist(1, points.length - 1) : <LatLng>[];
    final params = <String, String>{
      'api': '1',
      'origin': _ll(origin),
      'destination': _ll(dest),
      'travelmode': 'driving',
    };
    if (waypoints.isNotEmpty) {
      params['waypoints'] = waypoints.map(_ll).join('|');
    }
    return Uri.https('www.google.com', '/maps/dir/', params);
  }

  /// Apple Maps URL. Více zastávek přes `daddr` spojené `+to:` (funguje v Apple
  /// Maps appce). dirflg=d → autem.
  static Uri appleMaps(List<LatLng> points) {
    final saddr = _ll(points.first);
    final daddr = points.sublist(1).map(_ll).join('+to:');
    return Uri.parse('https://maps.apple.com/?saddr=$saddr&daddr=$daddr&dirflg=d');
  }

  /// Dostupné cíle — Mapy.com, Google Maps i Apple Maps (na všech platformách;
  /// OS otevře appku, nebo web).
  static List<RouteExportTarget> targets() => const [
        RouteExportTarget.mapy,
        RouteExportTarget.googleMaps,
        RouteExportTarget.appleMaps,
      ];

  static Future<bool> open(RouteExportTarget target, List<LatLng> points) async {
    if (points.length < 2) return false;
    final uri = switch (target) {
      RouteExportTarget.mapy => mapy(points),
      RouteExportTarget.googleMaps => googleMaps(points),
      RouteExportTarget.appleMaps => appleMaps(points),
    };
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[routes] export launch selhal: $e');
      return false;
    }
  }
}

enum RouteExportTarget {
  mapy,
  googleMaps,
  appleMaps;

  String get label => switch (this) {
        RouteExportTarget.mapy => 'Mapy.com',
        RouteExportTarget.googleMaps => 'Google Maps',
        RouteExportTarget.appleMaps => 'Apple Maps',
      };

  String get emoji => switch (this) {
        RouteExportTarget.mapy => '🧭',
        RouteExportTarget.googleMaps => '🗺️',
        RouteExportTarget.appleMaps => '🍎',
      };
}
