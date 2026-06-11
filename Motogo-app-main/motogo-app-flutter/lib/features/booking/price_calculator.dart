import 'dart:convert';
import 'dart:math' show pi, sin, cos, sqrt, atan2;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../catalog/moto_model.dart';
import 'booking_models.dart';

/// Branch coordinates (Mezná 9, 393 01 Pelhřimov).
/// Mezná leží ~9 km jižně od Pelhřimova (obec, okres Pelhřimov).
/// Pozn.: dřívější hodnota 49.4147, 15.2953 byla chybně u Křemešníku /
/// Proseče pod Křemešníkem (~10 km od Mezné) → přistavení/odvoz počítalo
/// nesmyslné vzdálenosti (sousední adresa Mezné ~15 km, Proseč ~0 km).
const branchLat = 49.3464;
const branchLng = 15.2119;

const _mapyKey = 'whg1ilj203oYhmsqkBHVtUqpk-tYr0E-HFTx4lGdue0';
const _mapyHeaders = <String, String>{
  'Accept': 'application/json',
  'X-Mapy-Api-Key': _mapyKey,
};

/// Real road distance (km) from branch (Mezná) to [lat],[lng].
/// Vrací SKUTEČNOU vzdálenost autem po silnici (nejrychlejší trasa bez provozu),
/// žádný odhad přes koeficient:
/// 1) Mapy.cz Routing (car_fast) — primární zdroj, reálná silniční trasa v ČR.
/// 2) OSRM (driving) — záloha, také reálná silniční trasa.
/// 3) Vzdušná čára BEZ koeficientu — jen krajní nouze, když obě API nedostupné.
Future<double> routeKmFromBranch(double lat, double lng) async {
  debugPrint('═══ [ROUTING] routeKmFromBranch() start ═══');
  debugPrint('[ROUTING] from branch ($branchLat, $branchLng) → to ($lat, $lng)');

  // Vzdušná čára — slouží POUZE k detekci jednotky (silniční trasa nemůže být
  // kratší než vzdušná čára) a jako krajní fallback, NIKDY jako odhad.
  final straightKm = _haversine(branchLat, branchLng, lat, lng);
  debugPrint('[ROUTING] straight-line baseline: ${straightKm.toStringAsFixed(1)}km');

  // 1) Mapy.cz Routing — fastest car route (car_fast = nejrychlejší bez provozu)
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
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      num? rawLength;
      if (data is List && data.isNotEmpty) {
        rawLength = data[0]['length'] as num?;
      } else if (data is Map) {
        rawLength = (data['length'] as num?) ??
            (data['route']?['length'] as num?);
      }
      final km = _normalizeRouteKm(rawLength, straightKm);
      if (km != null) {
        debugPrint('[ROUTING] ✓ Mapy.cz car_fast: ${km.toStringAsFixed(1)}km');
        return km;
      }
      debugPrint('[ROUTING] ✗ Mapy.cz: length=$rawLength (invalid)');
    }
  } catch (e) {
    debugPrint('[ROUTING] ✗ Mapy.cz error: $e');
  }

  // 2) OSRM fallback — také reálná silniční trasa
  try {
    final url = 'https://router.project-osrm.org/route/v1/driving/'
        '$branchLng,$branchLat;$lng,$lat?overview=false';
    debugPrint('[ROUTING] 2) OSRM URL: $url');
    final uri = Uri.parse(url);
    final res = await http.get(uri, headers: {
      'User-Agent': 'MotoGo24-App/1.0',
    }).timeout(const Duration(seconds: 10));
    debugPrint('[ROUTING] 2) OSRM status: ${res.statusCode}');
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final routes = data['routes'] as List?;
      if (routes != null && routes.isNotEmpty) {
        final dist = (routes[0]['distance'] as num).toDouble();
        if (dist > 0) {
          final km = dist / 1000; // OSRM always returns meters
          debugPrint('[ROUTING] ✓ OSRM: ${km.toStringAsFixed(1)}km');
          return km;
        }
      }
    }
  } catch (e) {
    debugPrint('[ROUTING] ✗ OSRM error: $e');
  }

  // 3) Krajní nouze: obě routing API nedostupná → vzdušná čára BEZ koeficientu.
  final km = straightKm > 0 ? straightKm : 50.0;
  debugPrint('[ROUTING] 3) ⚠ routing API nedostupné → vzdušná čára ${km.toStringAsFixed(1)}km (bez koeficientu)');
  debugPrint('═══ [ROUTING] routeKmFromBranch() end → ${km.toStringAsFixed(1)}km ═══');
  return km;
}

/// Převede `length` z Mapy.cz routing na km. API vrací metry; jednotku hlídáme
/// fyzikálním invariantem — silniční trasa nemůže být kratší než vzdušná čára.
/// Pokud je metry→km výrazně kratší než vzdušná čára, hodnota už byla v km.
double? _normalizeRouteKm(num? rawLength, double straightKm) {
  if (rawLength == null || rawLength <= 0) return null;
  double km = rawLength.toDouble() / 1000; // předpoklad: metry
  if (straightKm > 0.5 && km < straightKm * 0.9) {
    km = rawLength.toDouble(); // hodnota už byla v km
  }
  return km;
}

/// Geocode [query] (full address) and return the candidate position nearest
/// to the branch.
///
/// Mapy.cz returns several matches for ambiguous place names — e.g. there are
/// multiple Czech villages called "Mezná". Requesting a single result can land
/// on a far-away homonym, inflating the delivery distance (the reported bug:
/// "Mezná 65" — the same village as the branch — was computed as ~15 km).
/// Fetching a handful of candidates and keeping the one closest to the branch
/// resolves to the intended place. Returns null on failure (caller falls back
/// to [estimateKm]).
Future<({double lat, double lng})?> geocodeNearestToBranch(String query) async {
  if (query.trim().length < 3) return null;
  try {
    final uri = Uri.parse('https://api.mapy.cz/v1/geocode'
        '?query=${Uri.encodeComponent(query)}'
        '&lang=cs&limit=8&locality=cz&apikey=$_mapyKey');
    final res = await http
        .get(uri, headers: _mapyHeaders)
        .timeout(const Duration(seconds: 5));
    debugPrint('[GEOCODE] "$query" status=${res.statusCode}');
    if (res.statusCode != 200) return null;
    final items = (jsonDecode(res.body)['items'] as List?) ?? [];
    ({double lat, double lng})? best;
    double bestKm = double.infinity;
    for (final it in items) {
      final pos = (it as Map)['position'];
      final lat = (pos?['lat'] as num?)?.toDouble();
      final lng = (pos?['lon'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final d = _haversine(branchLat, branchLng, lat, lng);
      if (d < bestKm) {
        bestKm = d;
        best = (lat: lat, lng: lng);
      }
    }
    debugPrint('[GEOCODE] ${items.length} candidates → nearest '
        '${bestKm.isFinite ? '${bestKm.toStringAsFixed(1)}km' : 'none'}');
    return best;
  } catch (e) {
    debugPrint('[GEOCODE] ✗ error: $e');
    return null;
  }
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
    // Věrnostní rank — sleva platí JEN pro rezervace v aplikaci.
    int loyaltyPercent = 0,
    int loyaltyLevel = 0,
    String? loyaltyRankName,
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

    // ── Věrnostní sleva (ranky, JEN app rezervace) ──
    // Základ: pronájem + příslušenství (bez přistavení a pojištění).
    final loyaltyBase = basePrice + extrasTotal;
    final loyaltyApplied = loyaltyPercent > 0
        ? (loyaltyBase * loyaltyPercent / 100).roundToDouble()
        : 0.0;

    // Věrnostní sleva se KOMBINUJE s promo kódy i dárkovými vouchery —
    // slevy se sčítají. Kódy se počítají ze zbytku po věrnostní slevě
    // (uvnitř calcDiscounts: fixní částky první, procenta ze zbytku).
    final discountTotal = calcDiscounts(
      discounts,
      (fullBase - loyaltyApplied).clamp(0, double.infinity).toDouble(),
    );

    final total =
        (fullBase - discountTotal - loyaltyApplied).clamp(0, double.infinity);

    return PriceBreakdown(
      basePrice: basePrice,
      extrasTotal: extrasTotal,
      pickupDeliveryFee: pickupDeliveryFee,
      returnDeliveryFee: returnDeliveryFee,
      insuranceFee: insuranceFee,
      discountTotal: discountTotal,
      total: total.toDouble(),
      days: days,
      loyaltyDiscount: loyaltyApplied,
      loyaltyPercent: loyaltyApplied > 0 ? loyaltyPercent : 0,
      loyaltyLevel: loyaltyApplied > 0 ? loyaltyLevel : 0,
      loyaltyRankName: loyaltyApplied > 0 ? loyaltyRankName : null,
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
