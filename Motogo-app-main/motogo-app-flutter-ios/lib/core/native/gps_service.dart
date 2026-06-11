import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// GPS service — mirrors native-gps.js + _sosGetGPS from ui-sos-core.js.
/// Provides location with high-accuracy first, low-accuracy fallback.
/// Uses geolocator 10.x API (desiredAccuracy parameter).
class GpsService {
  GpsService._();

  /// Check & request location permission if needed.
  /// If denied → requests via system dialog.
  static Future<bool> ensurePermission() async {
    debugPrint('[GPS_SVC] ensurePermission()');
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    debugPrint('[GPS_SVC] locationServiceEnabled: $serviceEnabled');
    if (!serviceEnabled) {
      debugPrint('[GPS_SVC] ✗ location service OFF → opening settings');
      await Geolocator.openLocationSettings();
      return false;
    }

    var perm = await Geolocator.checkPermission();
    debugPrint('[GPS_SVC] checkPermission: $perm');

    if (perm == LocationPermission.denied) {
      debugPrint('[GPS_SVC] permission denied → requesting...');
      perm = await Geolocator.requestPermission();
      debugPrint('[GPS_SVC] requestPermission result: $perm');
    }

    if (perm == LocationPermission.deniedForever) {
      debugPrint('[GPS_SVC] ✗ deniedForever → need app settings');
      await Geolocator.openAppSettings();
      return false;
    }

    final ok = perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always;
    debugPrint('[GPS_SVC] permission result: $ok ($perm)');
    return ok;
  }

  /// Get current position with fallback.
  /// Mirrors _cordovaGetPosition from native-fingerprint.js:
  /// 1. High accuracy (30s timeout)
  /// 2. Low accuracy fallback (30s timeout)
  static Future<Position?> getCurrentPosition() async {
    debugPrint('[GPS_SVC] getCurrentPosition() start');
    final hasPermission = await ensurePermission();
    if (!hasPermission) {
      debugPrint('[GPS_SVC] ✗ no permission → trying lastKnown');
      return _getLastKnown();
    }

    try {
      debugPrint('[GPS_SVC] trying HIGH accuracy (15s timeout)...');
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      debugPrint('[GPS_SVC] ✓ HIGH: lat=${pos.latitude} lng=${pos.longitude} '
          'accuracy=${pos.accuracy}m');
      return pos;
    } catch (e) {
      debugPrint('[GPS_SVC] ✗ HIGH failed: $e');
      // Fallback: low accuracy
      try {
        debugPrint('[GPS_SVC] trying LOW accuracy (15s timeout)...');
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 15),
        );
        debugPrint('[GPS_SVC] ✓ LOW: lat=${pos.latitude} lng=${pos.longitude} '
            'accuracy=${pos.accuracy}m');
        return pos;
      } catch (e2) {
        debugPrint('[GPS_SVC] ✗ LOW failed: $e2');
        debugPrint('[GPS_SVC] → trying lastKnown as final fallback');
        return _getLastKnown();
      }
    }
  }

  /// Try to get last known position (cached).
  static Future<Position?> _getLastKnown() async {
    try {
      final pos = await Geolocator.getLastKnownPosition();
      debugPrint('[GPS_SVC] lastKnown: ${pos != null ? "lat=${pos.latitude} lng=${pos.longitude}" : "null"}');
      return pos;
    } catch (e) {
      debugPrint('[GPS_SVC] ✗ lastKnown error: $e');
      return null;
    }
  }

  /// Get position as lat/lng map (null-safe).
  static Future<({double? lat, double? lng})> getLatLng() async {
    final pos = await getCurrentPosition();
    return (lat: pos?.latitude, lng: pos?.longitude);
  }

  /// Reverse geocode via Nominatim OSM (free, no API key).
  /// Mirrors the Nominatim fallback from native-fingerprint.js.
  static Future<GeoAddress?> reverseGeocode(
    double lat,
    double lng,
  ) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=json&lat=$lat&lon=$lng&zoom=18&addressdetails=1',
      );
      final response = await http.get(uri, headers: {
        'User-Agent': 'MotoGo24-App/1.0',
      }).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      final addr = data['address'] as Map<String, dynamic>?;
      if (addr == null) return null;

      return GeoAddress(
        street: addr['road'] as String?,
        houseNum: addr['house_number'] as String?,
        city: (addr['city'] ?? addr['town'] ?? addr['village']) as String?,
        zip: addr['postcode'] as String?,
        lat: lat,
        lng: lng,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Geocoded address result.
class GeoAddress {
  final String? street;
  final String? houseNum;
  final String? city;
  final String? zip;
  final double lat;
  final double lng;

  const GeoAddress({
    this.street,
    this.houseNum,
    this.city,
    this.zip,
    required this.lat,
    required this.lng,
  });
}
