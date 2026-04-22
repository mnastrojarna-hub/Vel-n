import 'dart:convert';
import 'dart:math' show pi, sin, cos, sqrt, atan2;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../catalog/moto_model.dart';
import 'booking_models.dart';

/// Branch coordinates (Mezná 9, 393 01 Pelhřimov).
const branchLat = 49.4147;
const branchLng = 15.2953;

const _mapyKey = 'whg1ilj203oYhmsqkBHVtUqpk-tYr0E-HFTx4lGdue0';
const _mapyHeaders = <String, String>{
  'Accept': 'application/json',
  'X-Mapy-Api-Key': _mapyKey,
};

/// Real road distance (km) from branch (Mezná) to [lat],[lng].
/// 1) Mapy.cz Routing (car_fast) — nejpřesnější po silnici v ČR.
/// 2) OSRM fallback.
/// 3) Haversine × 1.3 (přímá vzdálenost × koeficient).
Future<double> routeKmFromBranch(double lat, double lng) async {
  debugPrint('═══ [ROUTING] routeKmFromBranch() start ═══');
  debugPrint('[ROUTING] from branch ($branchLat, $branchLng) → to ($lat, $lng)');

  // Haversine baseline for sanity checks
  final haversineKm = _haversine(branchLat, branchLng, lat, lng);
  debugPrint('[ROUTING] Haversine baseline: ${haversineKm.toStringAsFixed(1)}km straight');

  // 1) Mapy.cz Routing — fastest car route
  try {
    final url = 'https://api.mapy.cz/v1/routing/route'
        '?start=$branchLng,$branchLat'
        '&end=$lng,$lat'
        '&routeType=car_fast&lang=cs'
        '&apikey=$_mapyKey';
    debugPrint('[ROUTING] 1) Mapy.cz URL: $url');
    final uri = Uri.parse(url);
    final res = await http.get(uri, headers: _mapyHeaders)
        .timeout(const Duration(seconds: 8));
    debugPrint('[ROUTING] 1) Mapy.cz status: ${res.statusCode}');
    debugPrint('[ROUTING] 1) Mapy.cz body (first 500): '
        '${res.body.length > 500 ? res.body.substring(0, 500) : res.body}');
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      debugPrint('[ROUTING] 1) parsed type: ${data.runtimeType}');
      num? rawLength;
      if (data is List && data.isNotEmpty) {
        rawLength = data[0]['length'] as num?;
        debugPrint('[ROUTING] 1) Array[0].length=$rawLength');
      } else if (data is Map) {
        rawLength = (data['length'] as num?) ??
            (data['route']?['length'] as num?);
        debugPrint('[ROUTING] 1) keys=${(data as Map).keys.toList()} length=$rawLength');
      }
      if (rawLength != null && rawLength > 0) {
        double km = rawLength.toDouble() / 1000; // assume meters
        debugPrint('[ROUTING] 1) raw=$rawLength → ${km.toStringAsFixed(1)}km (assuming meters)');

        // Sanity check: if API result is < 30% of Haversine,
        // the API probably returned km not meters
        if (haversineKm > 2 && km < haversineKm * 0.3) {
          km = rawLength.toDouble(); // treat as km directly
          debugPrint('[ROUTING] 1) ⚠ too small vs Haversine → treating as km: ${km.toStringAsFixed(1)}km');
        }
        // Plausibility window — applies for ALL distances, including
        // same-village addresses (Haversine ~ 0 km) where a stray
        // routing result like 14 km used to leak through.
        final maxReasonable = haversineKm > 2
            ? haversineKm * 5
            : haversineKm + 3; // allow up to 3 km detour in/near village
        final minReasonable = haversineKm > 2 ? haversineKm * 0.5 : 0.0;
        if (km < minReasonable || km > maxReasonable) {
          debugPrint('[ROUTING] 1) ⚠ Mapy.cz ${km.toStringAsFixed(1)}km '
              'outside plausible window '
              '(${minReasonable.toStringAsFixed(1)}–${maxReasonable.toStringAsFixed(1)}km, '
              'Haversine ${haversineKm.toStringAsFixed(1)}km) — skipping');
        } else {
          debugPrint('[ROUTING] ✓ Mapy.cz: ${km.toStringAsFixed(1)}km');
          return km;
        }
      }
      debugPrint('[ROUTING] ✗ Mapy.cz: rawLength=$rawLength (invalid)');
    }
  } catch (e) {
    debugPrint('[ROUTING] ✗ Mapy.cz error: $e');
  }

  // 2) OSRM fallback
  try {
    final url = 'https://router.project-osrm.org/route/v1/driving/'
        '$branchLng,$branchLat;$lng,$lat?overview=false';
    debugPrint('[ROUTING] 2) OSRM URL: $url');
    final uri = Uri.parse(url);
    final res = await http.get(uri, headers: {
      'User-Agent': 'MotoGo24-App/1.0',
    }).timeout(const Duration(seconds: 10));
    debugPrint('[ROUTING] 2) OSRM status: ${res.statusCode}');
    debugPrint('[ROUTING] 2) OSRM body (first 300): '
        '${res.body.length > 300 ? res.body.substring(0, 300) : res.body}');
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final routes = data['routes'] as List?;
      debugPrint('[ROUTING] 2) OSRM routes count: ${routes?.length}');
      if (routes != null && routes.isNotEmpty) {
        final dist = (routes[0]['distance'] as num).toDouble();
        if (dist > 0) {
          final km = dist / 1000; // OSRM always returns meters
          debugPrint('[ROUTING] 2) OSRM: ${dist.toStringAsFixed(0)}m = ${km.toStringAsFixed(1)}km');
          // Same plausibility window as Mapy.cz branch above
          final maxReasonable = haversineKm > 2
              ? haversineKm * 5
              : haversineKm + 3;
          final minReasonable = haversineKm > 2 ? haversineKm * 0.5 : 0.0;
          if (km < minReasonable || km > maxReasonable) {
            debugPrint('[ROUTING] 2) ⚠ OSRM ${km.toStringAsFixed(1)}km '
                'outside plausible window '
                '(${minReasonable.toStringAsFixed(1)}–${maxReasonable.toStringAsFixed(1)}km, '
                'Haversine ${haversineKm.toStringAsFixed(1)}km) — skipping');
          } else {
            debugPrint('[ROUTING] ✓ OSRM: ${km.toStringAsFixed(1)}km');
            return km;
          }
        }
        debugPrint('[ROUTING] ✗ OSRM: distance=$dist (invalid)');
      }
    }
  } catch (e) {
    debugPrint('[ROUTING] ✗ OSRM error: $e');
  }

  // 3) Haversine × 1.3 fallback
  final straight = _haversine(branchLat, branchLng, lat, lng);
  final km = straight > 0 ? straight * 1.3 : 50.0;
  debugPrint('[ROUTING] 3) Haversine: straight=${straight.toStringAsFixed(1)}km × 1.3 = ${km.toStringAsFixed(1)}km');
  debugPrint('═══ [ROUTING] routeKmFromBranch() end → ${km.toStringAsFixed(1)}km ═══');
  return km;
}

double _haversine(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLon = (lon2 - lon1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) *
          cos(lat2 * pi / 180) *
          sin(dLon / 2) *
          sin(dLon / 2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}

/// Price calculator — IDENTICAL to cart-booking-price.js + calc_booking_price_v2.
/// Per-day pricing (Mon-Sun), inclusive start+end, delivery, extras, discounts.
class PriceCalculator {
  PriceCalculator._();

  /// Base delivery fee — naložení a složení (Kč).
  static const double deliveryBase = 1000;

  /// Per-km rate (Kč/km).
  static const double deliveryPerKm = 40;

  /// Delivery fee: 1 000 Kč (naložení/složení) + 40 Kč/km.
  static double calcDeliveryFee(double km) {
    return deliveryBase + km * deliveryPerKm;
  }

  /// Calculate total rental price for date range (inclusive start+end).
  /// Mirrors calcTotalPrice() from cart-booking-price.js.
  static double calcBasePrice(DayPrices? prices, DateTime start, DateTime end) {
    if (prices == null) return 0;
    return prices.totalForRange(start, end);
  }

  /// Calculate complete price breakdown.
  /// Mirrors recalcTotal() from cart-booking-price.js.
  static PriceBreakdown calculate({
    required DayPrices? prices,
    required DateTime? startDate,
    required DateTime? endDate,
    required List<SelectedExtra> extras,
    required double pickupDeliveryFee,
    required double returnDeliveryFee,
    required List<AppliedDiscount> discounts,
    double insuranceFee = 0,
  }) {
    if (startDate == null || endDate == null) {
      return const PriceBreakdown(
        basePrice: 0,
        extrasTotal: 0,
        pickupDeliveryFee: 0,
        returnDeliveryFee: 0,
        discountTotal: 0,
        total: 0,
        days: 0,
      );
    }

    final days = endDate.difference(startDate).inDays + 1; // inclusive
    final basePrice = calcBasePrice(prices, startDate, endDate);
    // Extras = flat price per rental (NOT multiplied by days)
    // Matches Capacitor: extraTotal = sum of data-price for checked items
    final extrasTotal = extras.fold<double>(
      0,
      (sum, e) => sum + e.price * e.quantity,
    );
    final deliveryTotal = pickupDeliveryFee + returnDeliveryFee;

    // Full base before discounts
    final fullBase = basePrice + extrasTotal + deliveryTotal + insuranceFee;

    // Apply discounts — mirrors _recalcBookingDiscounts()
    // 1) Fixed amounts first, 2) Percentages on remainder
    final discountTotal = calcDiscounts(discounts, fullBase);

    final total = (fullBase - discountTotal).clamp(0, double.infinity);

    return PriceBreakdown(
      basePrice: basePrice,
      extrasTotal: extrasTotal,
      pickupDeliveryFee: pickupDeliveryFee,
      returnDeliveryFee: returnDeliveryFee,
      insuranceFee: insuranceFee,
      discountTotal: discountTotal,
      total: total.toDouble(),
      days: days,
    );
  }

  /// Apply discounts in correct order.
  /// Mirrors _recalcBookingDiscounts() from cart-booking-discount.js.
  /// Fixed discounts first, then percentage on remaining amount.
  static double calcDiscounts(
    List<AppliedDiscount> discounts,
    double fullBase,
  ) {
    if (discounts.isEmpty) return 0;

    double remaining = fullBase;
    double totalDiscount = 0;

    // 1) Fixed-amount discounts first (in order applied)
    for (final d in discounts.where((d) => d.type == DiscountType.fixed)) {
      final amt = d.value.clamp(0, remaining);
      d.calculatedAmount = amt.toDouble();
      totalDiscount += amt;
      remaining -= amt;
    }

    // 2) Percentage discounts on remaining amount
    for (final d in discounts.where((d) => d.type == DiscountType.percent)) {
      final amt = remaining * d.value / 100;
      d.calculatedAmount = amt.toDouble();
      totalDiscount += amt;
      remaining -= amt;
    }

    return totalDiscount;
  }
}

/// KM estimates for Czech cities — mirrors KM_ESTIMATES from data/motos.js.
/// Used as fallback when geocoding API is unavailable.
const kmEstimates = <String, int>{
  'Praha': 130, 'Brno': 90, 'Jihlava': 30, 'Třebíč': 45,
  'České Budějovice': 70, 'Havlíčkův Brod': 50, 'Humpolec': 15,
  'Mezná': 0, 'Pelhřimov': 10, 'Tábor': 35, 'Ostrava': 280,
  'Plzeň': 200, 'Liberec': 210, 'Olomouc': 180, 'Hradec Králové': 170,
  'Ústí nad Labem': 200, 'Pardubice': 120, 'Zlín': 180,
  'Kladno': 145, 'Karlovy Vary': 220, 'Znojmo': 110,
  'Příbram': 100, 'Kolín': 120, 'Písek': 55,
  'Žďár nad Sázavou': 55, 'Benešov': 100, 'Kutná Hora': 110,
  'Pacov': 15, 'Kamenice nad Lipou': 20,
};

/// Estimate km from city name (fallback).
int estimateKm(String address) {
  final lower = address.toLowerCase();
  for (final entry in kmEstimates.entries) {
    if (lower.contains(entry.key.toLowerCase())) return entry.value;
  }
  return 50; // default estimate
}
