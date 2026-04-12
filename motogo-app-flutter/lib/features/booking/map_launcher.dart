import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'widgets/map_picker.dart';
import 'price_calculator.dart';

/// Opens map picker and returns address + real distance.
Future<MapResult?> launchMapPicker(BuildContext context) async {
  final result = await MapPickerScreen.show(context);
  if (result == null) return null;

  String city = result.city;
  String addr = result.street;
  double? lat = result.lat;
  double? lng = result.lng;

  // Reverse geocode if city empty
  if (city.isEmpty && lat != null && lng != null) {
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

  // Calculate REAL distance via routing API
  double km;
  if (lat != null && lng != null) {
    km = await _realRouteKm(lat, lng);
  } else {
    km = estimateKm(city).toDouble();
  }
  final fee = PriceCalculator.calcDeliveryFee(km);

  return MapResult(
    city: city, address: addr, km: km, fee: fee);
}

/// Real road distance from branch (Mezná) via OSRM routing.
Future<double> _realRouteKm(double lat, double lng) async {
  // 1) OSRM
  try {
    final uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${branchLng},$branchLat;$lng,$lat?overview=false');
    final res = await http.get(uri)
        .timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final routes = data['routes'] as List?;
      if (routes != null && routes.isNotEmpty) {
        return (routes[0]['distance'] as num).toDouble() / 1000;
      }
    }
  } catch (_) {}
  // 2) Fallback
  return 50;
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
