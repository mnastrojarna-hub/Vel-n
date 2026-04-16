import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase_client.dart';
import '../auth/auth_provider.dart';
import '../catalog/moto_model.dart';
import '../reservations/reservation_provider.dart';
import 'booking_models.dart';
import 'booking_validator.dart';
import 'price_calculator.dart';

/// Central booking state — mirrors global vars from booking-logic.js.
final bookingDraftProvider = StateProvider<BookingDraft>(
  (_) => BookingDraft(),
);

/// Selected motorcycle for booking.
final bookingMotoProvider = StateProvider<Motorcycle?>((_) => null);

/// Pickup delivery fee (calculated from address distance).
final pickupDelivFeeProvider = StateProvider<double>((_) => 0);

/// Pickup distance in km.
final pickupDistKmProvider = StateProvider<double>((_) => 0);

/// Return delivery fee.
final returnDelivFeeProvider = StateProvider<double>((_) => 0);

/// Return distance in km.
final returnDistKmProvider = StateProvider<double>((_) => 0);

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
    return DiscountResult(success: false, messageKey: 'enterCodeHint');
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
        messageKey: 'discountApplied',
        messageArgs: {
          'value': type == 'percent' ? '$value%' : '${value.toStringAsFixed(0)} Kč',
        },
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
        messageKey: 'voucherApplied',
        messageArgs: {'value': '${value.toStringAsFixed(0)} Kč'},
      );
    }
  } catch (_) {}

  return DiscountResult(
    success: false,
    messageKey: 'invalidCode',
    messageArgs: {'code': upperCode},
  );
}

class DiscountResult {
  final bool success;
  final AppliedDiscount? discount;
  final String messageKey;
  final Map<String, String> messageArgs;

  const DiscountResult({
    required this.success,
    this.discount,
    required this.messageKey,
    this.messageArgs = const {},
  });

  /// Resolve message using i18n translations.
  String message(String Function(String) tr) {
    var msg = tr(messageKey);
    for (final e in messageArgs.entries) {
      msg = msg.replaceAll('{${e.key}}', e.value);
    }
    return msg;
  }
}

/// License validation — checks user's ŘP against moto requirement.
/// Returns null if OK, or error message.
final licenseValidationProvider = Provider<String?>((ref) {
  final moto = ref.watch(bookingMotoProvider);
  if (moto == null) return null;

  final profile = ref.watch(profileProvider).valueOrNull;
  if (profile == null) return null;

  // Parse license_group array from profile
  final rawGroups = profile['license_group'];
  final userGroups = <String>[];
  if (rawGroups is List) {
    for (final g in rawGroups) {
      if (g != null) userGroups.add(g.toString());
    }
  }

  return BookingValidator.checkLicense(
    userLicenseGroups: userGroups,
    motoLicense: moto.licenseRequired,
  );
});

/// Overlap validation — checks user's existing reservations against new dates.
/// Returns null if OK, or error message.
final overlapValidationProvider = Provider<String?>((ref) {
  final moto = ref.watch(bookingMotoProvider);
  final draft = ref.watch(bookingDraftProvider);
  if (moto == null || draft.startDate == null || draft.endDate == null) {
    return null;
  }

  final reservations = ref.watch(reservationsProvider).valueOrNull;
  if (reservations == null) return null;

  final isChildrens = moto.licenseRequired == 'N';

  return BookingValidator.checkOverlap(
    userReservations: reservations,
    startDate: draft.startDate!,
    endDate: draft.endDate!,
    isChildrensMoto: isChildrens,
  );
});

/// Combined booking validation error (license + overlap).
/// Returns null if everything is OK.
final bookingValidationErrorProvider = Provider<String?>((ref) {
  return ref.watch(licenseValidationProvider) ??
      ref.watch(overlapValidationProvider);
});

/// Fetch extras catalog from Supabase.
final extrasCatalogProvider =
    FutureProvider<List<ExtraCatalogItem>>((ref) async {
  try {
    final res = await MotoGoSupabase.client
        .from('extras_catalog')
        .select()
        .order('name');

    final items = (res as List)
        .map((e) => ExtraCatalogItem.fromJson(e as Map<String, dynamic>))
        .toList();

    return items.isNotEmpty ? items : defaultExtras;
  } catch (_) {
    return defaultExtras;
  }
});
