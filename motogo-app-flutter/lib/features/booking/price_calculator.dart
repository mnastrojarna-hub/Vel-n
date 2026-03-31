import '../catalog/moto_model.dart';
import 'booking_models.dart';

/// Price calculator — IDENTICAL to cart-booking-price.js + calc_booking_price_v2.
/// Per-day pricing (Mon-Sun), inclusive start+end, delivery, extras, discounts.
class PriceCalculator {
  PriceCalculator._();

  /// Base delivery fee constant (Kč).
  static const double deliveryBase = 1000;

  /// Per-km rate (round trip: km × 2 × 20 = km × 40).
  static const double deliveryPerKm = 40;

  /// Calculate delivery fee from distance.
  /// Formula: 1000 + km × 2 × 20 (mirrors _calcDeliveryFee from address-api.js).
  static double calcDeliveryFee(double km) {
    return deliveryBase + km * 2 * 20;
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
    final extrasTotal = extras.fold<double>(
      0,
      (sum, e) => sum + e.price * e.quantity,
    );
    final deliveryTotal = pickupDeliveryFee + returnDeliveryFee;

    // Full base before discounts
    final fullBase = basePrice + extrasTotal + deliveryTotal + insuranceFee;

    // Apply discounts — mirrors _recalcBookingDiscounts()
    // 1) Fixed amounts first, 2) Percentages on remainder
    final discountTotal = _calcDiscounts(discounts, fullBase);

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
  static double _calcDiscounts(
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
