import '../catalog/moto_model.dart';
import '../loyalty/loyalty_provider.dart';
import 'booking_models.dart';
import 'price_calculator.dart';

/// Cena pro náhledy MIMO rezervační formulář (domovský „funnel", kalkulačka,
/// karty motorek): `PriceCalculator.calculate` s PŘESNĚ těmi argumenty, které
/// `priceBreakdownProvider` dává čerstvému návrhu rezervace (bez doplňků,
/// bez přistavení, bez slev kromě věrnostní) — rezervační formulář pak ukáže
/// stejnou částku. [pickupTime] null = výchozí návrh (bez slevy 1. dne),
/// '12:00' = vyzvednutí od poledne (sleva 50 % na 1. den, ≥ 2 dny).
PriceBreakdown quoteFor(
  Motorcycle moto,
  DateTime start,
  DateTime end, {
  String? pickupTime,
  LoyaltyStatus? loyalty,
}) =>
    PriceCalculator.calculate(
      prices: moto.prices,
      startDate: start,
      endDate: end,
      extras: const [],
      pickupDeliveryFee: 0,
      returnDeliveryFee: 0,
      discounts: const [],
      loyaltyPercent: loyalty?.percent ?? 0,
      loyaltyLevel: loyalty?.level ?? 0,
      loyaltyRankName: loyalty?.rankName,
      pickupTime: pickupTime,
    );

/// Ceníková cena bez věrnostní slevy (přeškrtnutá vedle „Tvoje cena").
PriceBreakdown listQuoteFor(Motorcycle moto, DateTime start, DateTime end, {String? pickupTime}) =>
    quoteFor(moto, start, end, pickupTime: pickupTime);
