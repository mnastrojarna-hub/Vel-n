import 'dart:convert';
import 'dart:math' show pi, sin, cos, sqrt, atan2;
import 'package:http/http.dart' as http;

import '../catalog/moto_model.dart';
import 'booking_models.dart';

/// Branch coordinates (Mezná 9, 393 01 Pelhřimov).
const branchLat = 49.4147;
const branchLng = 15.2953;

const _mapyKey = 'Ag9d2QJD0i8_fA07r6GDDaZ4qV9aZDGMhWn_HhQ_rFs';

/// Real road distance (km) from branch (Mezná) to [lat],[lng].
/// 1) Mapy.cz Routing (car_fast) — nejpřesnější po silnici v ČR.
/// 2) OSRM fallback.
/// 3) Haversine × 1.3 (přímá vzdálenost × koeficient).
Future<double> routeKmFromBranch(double lat, double lng) async {
  // 1) Mapy.cz Routing — fastest car route
  try {
    final uri = Uri.parse(
        'https://api.mapy.cz/v1/routing/route'
        '?start=$branchLng,$branchLat'
        '&end=$lng,$lat'
        '&routeType=car_fast&lang=cs'
        '&apikey=$_mapyKey');
    final res = await http.get(uri).timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      // Mapy.cz returns { length: meters } or { route: { length } }
      final meters = (data['length'] as num?)?.toDouble() ??
          (data['route']?['length'] as num?)?.toDouble();
      if (meters != null && meters > 0) return meters / 1000;
    }
  } catch (_) {}

  // 2) OSRM fallback
  try {
    final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '$branchLng,$branchLat;$lng,$lat?overview=false');
    final res = await http.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final routes = data['routes'] as List?;
      if (routes != null && routes.isNotEmpty) {
        final meters = (routes[0]['distance'] as num).toDouble();
        if (meters > 0) return meters / 1000;
      }
    }
  } catch (_) {}

  // 3) Haversine × 1.3 fallback
  final straight = _haversine(branchLat, branchLng, lat, lng);
  return straight > 0 ? straight * 1.3 : 50;
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
