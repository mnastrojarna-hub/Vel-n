import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'widgets/map_picker.dart';
import 'price_calculator.dart';

const _mapyKey = 'Ag9d2QJD0i8_fA07r6GDDaZ4qV9aZDGMhWn_HhQ_rFs';
const _mapyHeaders = <String, String>{
  'Accept': 'application/json',
  'X-Mapy-Api-Key': _mapyKey,
};

/// Opens map picker and returns address + real distance.
Future<MapResult?> launchMapPicker(BuildContext context) async {
  debugPrint('═══ [MAP_LAUNCH] launchMapPicker() ═══');
  final result = await MapPickerScreen.show(context);
  if (result == null) {
    debugPrint('[MAP_LAUNCH] user cancelled');
    return null;
  }

  debugPrint('[MAP_LAUNCH] picker returned: lat=${result.lat} lng=${result.lng}');
  debugPrint('[MAP_LAUNCH] picker returned: street="${result.street}" '
      'city="${result.city}" zip="${result.zip}"');

  String city = result.city;
  String addr = result.street;
  double? lat = result.lat;
  double? lng = result.lng;

  // Reverse geocode if city empty — Mapy.cz primary, Nominatim fallback
  if (city.isEmpty && lat != null && lng != null) {
    bool filled = false;
    // 1) Mapy.cz rgeocode — precise for Czech addresses
    try {
      final mUri = Uri.parse(
        'https://api.mapy.cz/v1/rgeocode'
        '?lat=$lat&lon=$lng&lang=cs&apikey=$_mapyKey');
      final mRes = await http.get(mUri, headers: _mapyHeaders)
          .timeout(const Duration(seconds: 5));
      if (mRes.statusCode == 200) {
        final data = jsonDecode(mRes.body);
        final items = (data['items'] as List?) ?? [];
        if (items.isNotEmpty) {
          final item = items[0];
          final name = item['name'] as String? ?? '';
          final numMatch = RegExp(r'^(.+?)\s+(\d+\/?[\da-zA-Z]*)$').firstMatch(name);
          addr = numMatch != null
              ? '${numMatch.group(1)} ${numMatch.group(2)}' : name;
          final rs = (item['regionalStructure'] as List?) ?? [];
          for (final r in rs) {
            if (r['type'] == 'regional.municipality') {
              city = r['name'] as String? ?? '';
              break;
            }
          }
          filled = true;
        }
      }
    } catch (_) {}
    // 2) Nominatim fallback
    if (!filled) {
      try {
        final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse'
          '?format=json&lat=$lat&lon=$lng'
          '&zoom=18&addressdetails=1');
        final res = await http.get(uri,
          headers: {'User-Agent': 'MotoGo24/2.0'})
          .timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final a = (jsonDecode(res.body)['address']
              as Map<String, dynamic>?) ?? {};
          final road = a['road'] as String? ?? '';
          final house = a['house_number'] as String? ?? '';
          city = (a['city'] ?? a['town'] ??
              a['village'] ?? '') as String;
          addr = road.isNotEmpty
              ? '$road${house.isNotEmpty ? " $house" : ""}' : '';
        }
      } catch (_) {}
    }
  }

  // Calculate REAL distance via routing API (Mapy.cz → OSRM → Haversine)
  debugPrint('[MAP_LAUNCH] after rgeocode: city="$city" addr="$addr" lat=$lat lng=$lng');
  double km;
  if (lat != null && lng != null) {
    debugPrint('[MAP_LAUNCH] → routeKmFromBranch($lat, $lng)');
    km = await routeKmFromBranch(lat, lng);
  } else {
    km = estimateKm(city).toDouble();
    debugPrint('[MAP_LAUNCH] ✗ no coords → estimateKm("$city") = ${km.toStringAsFixed(0)}');
  }
  final fee = PriceCalculator.calcDeliveryFee(km);
  debugPrint('[MAP_LAUNCH] ✓ result: ${km.toStringAsFixed(1)}km, ${fee.toStringAsFixed(0)} Kč');

  return MapResult(
    city: city, address: addr, km: km, fee: fee);
}

class MapResult {
  final String city;
  final String address;
  final double km;
  final double fee;
  const MapResult({
    required this.city, required this.address,
    required this.km, required this.fee});
}
