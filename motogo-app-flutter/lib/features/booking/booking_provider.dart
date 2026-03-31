import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase_client.dart';
import '../catalog/moto_model.dart';
import 'booking_models.dart';
import 'price_calculator.dart';

/// Central booking state — mirrors global vars from booking-logic.js.
final bookingDraftProvider = StateProvider<BookingDraft>(
  (_) => BookingDraft(),
);

/// Selected motorcycle for booking.
final bookingMotoProvider = StateProvider<Motorcycle?>((_) => null);

/// Pickup delivery fee (calculated from address distance).
final pickupDelivFeeProvider = StateProvider<double>((_) => 0);

/// Return delivery fee.
final returnDelivFeeProvider = StateProvider<double>((_) => 0);

/// Price breakdown — recalculated whenever inputs change.
/// Mirrors recalcTotal() from cart-booking-price.js.
final priceBreakdownProvider = Provider<PriceBreakdown>((ref) {
  final draft = ref.watch(bookingDraftProvider);
  final moto = ref.watch(bookingMotoProvider);
  final pickupFee = ref.watch(pickupDelivFeeProvider);
  final returnFee = ref.watch(returnDelivFeeProvider);

  return PriceCalculator.calculate(
    prices: moto?.prices,
    startDate: draft.startDate,
    endDate: draft.endDate,
    extras: draft.extras,
    pickupDeliveryFee: draft.pickupMethod == 'delivery' ? pickupFee : 0,
    returnDeliveryFee: draft.returnMethod == 'delivery' ? returnFee : 0,
    discounts: draft.discounts,
  );
});

/// Validate and apply promo code or voucher.
/// Mirrors applyDiscount() from cart-booking-discount.js.
Future<DiscountResult> validateAndApplyCode(String code) async {
  final upperCode = code.trim().toUpperCase();
  if (upperCode.isEmpty) {
    return DiscountResult(success: false, message: 'Zadejte kód');
  }

  // 1. Try promo code via RPC
  try {
    final promoRes = await MotoGoSupabase.client
        .rpc('validate_promo_code', params: {'p_code': upperCode});

    if (promoRes != null && promoRes['valid'] == true) {
      final type = promoRes['type'] as String? ?? 'percent';
      final value = (promoRes['value'] as num?)?.toDouble() ?? 0;
      final id = promoRes['id'] as String?;

      return DiscountResult(
        success: true,
        discount: AppliedDiscount(
          code: upperCode,
          promoId: id,
          type: type == 'percent' ? DiscountType.percent : DiscountType.fixed,
          value: value,
        ),
        message: type == 'percent'
            ? 'Sleva $value% aplikována'
            : 'Sleva ${value.toStringAsFixed(0)} Kč aplikována',
      );
    }
  } catch (_) {}

  // 2. Try voucher code via RPC
  try {
    final voucherRes = await MotoGoSupabase.client
        .rpc('validate_voucher_code', params: {'p_code': upperCode});

    if (voucherRes != null && voucherRes['valid'] == true) {
      final value = (voucherRes['value'] as num?)?.toDouble() ?? 0;
      final id = voucherRes['id'] as String?;

      return DiscountResult(
        success: true,
        discount: AppliedDiscount(
          code: upperCode,
          promoId: id,
          type: DiscountType.fixed,
          value: value,
        ),
        message: 'Poukaz ${value.toStringAsFixed(0)} Kč aplikován',
      );
    }
  } catch (_) {}

  return DiscountResult(
    success: false,
    message: 'Neplatný kód "$upperCode"',
  );
}

class DiscountResult {
  final bool success;
  final AppliedDiscount? discount;
  final String message;

  const DiscountResult({
    required this.success,
    this.discount,
    required this.message,
  });
}

/// Fetch extras catalog from Supabase.
final extrasCatalogProvider =
    FutureProvider<List<ExtraCatalogItem>>((ref) async {
  try {
    final res = await MotoGoSupabase.client
        .from('extras_catalog')
        .select()
        .order('sort_order');

    final items = (res as List)
        .map((e) => ExtraCatalogItem.fromJson(e as Map<String, dynamic>))
        .toList();

    return items.isNotEmpty ? items : defaultExtras;
  } catch (_) {
    return defaultExtras;
  }
});
