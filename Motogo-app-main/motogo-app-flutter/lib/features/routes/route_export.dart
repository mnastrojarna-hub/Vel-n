import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

/// Přenos trasy se zastávkami do externí navigace — Apple Maps (iOS) / Google
/// Maps. Body = uspořádaný seznam (start pobočka → waypointy → u okruhu zpět).
class RouteExport {
  RouteExport._();

  static String _ll(LatLng p) =>
      '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}';

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

  static bool get _isIos => !kIsWeb && Platform.isIOS;

  /// Dostupné cíle pro aktuální platformu (iOS → Apple + Google, jinak Google).
  static List<RouteExportTarget> targets() {
    if (_isIos) {
      return const [RouteExportTarget.appleMaps, RouteExportTarget.googleMaps];
    }
    return const [RouteExportTarget.googleMaps];
  }

  static Future<bool> open(RouteExportTarget target, List<LatLng> points) async {
    if (points.length < 2) return false;
    final uri = switch (target) {
      RouteExportTarget.appleMaps => appleMaps(points),
      RouteExportTarget.googleMaps => googleMaps(points),
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
  appleMaps,
  googleMaps;

  String get label => switch (this) {
        RouteExportTarget.appleMaps => 'Apple Maps',
        RouteExportTarget.googleMaps => 'Google Maps',
      };

  String get emoji => switch (this) {
        RouteExportTarget.appleMaps => '🍎',
        RouteExportTarget.googleMaps => '🗺️',
      };
}
