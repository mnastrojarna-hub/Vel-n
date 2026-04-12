import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// GPS service — mirrors native-gps.js + _sosGetGPS from ui-sos-core.js.
/// Provides location with high-accuracy first, low-accuracy fallback.
/// Uses geolocator 10.x API (desiredAccuracy parameter).
class GpsService {
  GpsService._();

  /// Check and request location permission.
  static Future<bool> ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always;
  }

  /// Get current position with fallback.
  /// Mirrors _cordovaGetPosition from native-fingerprint.js:
  /// 1. High accuracy (30s timeout)
  /// 2. Low accuracy fallback (30s timeout)
  static Future<Position?> getCurrentPosition() async {
    final hasPermission = await ensurePermission();
    if (!hasPermission) {
      // Try last known position as fallback
      return _getLastKnown();
    }

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
    } catch (_) {
      // Fallback: low accuracy
      try {
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 15),
        );
      } catch (_) {
        // Final fallback: last known position
        return _getLastKnown();
      }
    }
  }

  /// Try to get last known position (cached).
  static Future<Position?> _getLastKnown() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
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
