import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase_client.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/i18n/translations.dart';
import '../auth/auth_provider.dart';
import '../catalog/moto_model.dart';
import '../loyalty/loyalty_provider.dart';
import '../reservations/reservation_provider.dart';
import 'booking_models.dart';
import 'booking_validator.dart';
import 'price_calculator.dart';
import '../../core/currency.dart';

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
  // Věrnostní rank — sleva 1–20 % JEN pro rezervace vytvořené v aplikaci.
  final loyalty = ref.watch(loyaltyStatusProvider).valueOrNull;

  return PriceCalculator.calculate(
    prices: moto?.prices,
    startDate: draft.startDate,
    endDate: draft.endDate,
    extras: draft.extras,
    pickupDeliveryFee: draft.pickupMethod == 'delivery' ? pickupFee : 0,
    returnDeliveryFee: draft.returnMethod == 'delivery' ? returnFee : 0,
    discounts: draft.discounts,
    loyaltyPercent: loyalty?.percent ?? 0,
    loyaltyLevel: loyalty?.level ?? 0,
    loyaltyRankName: loyalty?.rankName,
    pickupTime: draft.pickupTime,
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
          'value': type == 'percent' ? '$value%' : '${Money.czk(value)}',
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
          // Voucher = peníze → kombinuje se s věrnostní slevou (ranky).
          isVoucher: true,
        ),
        messageKey: 'voucherApplied',
        messageArgs: {'value': '${Money.czk(value)}'},
      );
    }
  } catch (_) {}

  // 3. Slevomat voucher přes edge fn — ověří u Slevomatu + založí voucher.
  try {
    final sl = await MotoGoSupabase.client.functions.invoke(
      'slevomat-voucher',
      body: {'action': 'check', 'code': upperCode},
    );
    final d = sl.data;
    if (d is Map && d['valid'] == true && d['voucher_id'] != null) {
      final value = (d['amount'] as num?)?.toDouble() ?? 0;
      return DiscountResult(
        success: true,
        discount: AppliedDiscount(
          code: upperCode,
          promoId: d['voucher_id'] as String?,
          type: DiscountType.fixed,
          value: value,
          isVoucher: true,
        ),
        messageKey: 'voucherApplied',
        messageArgs: {'value': '${Money.czk(value)}'},
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
    motoLicenseGroups: moto.licenseGroupsOrFallback,
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

/// Rental length validation — vynucuje min/max délku pronájmu z DB
/// (motorcycles.min_rental_days / max_rental_days), shodně s webem.
/// Returns null if OK, jinak lokalizovaná hláška.
final rentalLengthValidationProvider = Provider<String?>((ref) {
  final moto = ref.watch(bookingMotoProvider);
  final draft = ref.watch(bookingDraftProvider);
  if (moto == null || draft.startDate == null || draft.endDate == null) {
    return null;
  }
  final days = draft.endDate!.difference(draft.startDate!).inDays + 1;
  final lang = ref.watch(localeProvider).languageCode;
  String msg(String key, int n) =>
      (translations[lang]?[key] ?? translations['cs']?[key] ?? '')
          .replaceAll('{n}', '$n');

  final min = moto.minRentalDays;
  if (min != null && min > 1 && days < min) return msg('validationMinDays', min);
  final max = moto.maxRentalDays;
  if (max != null && max > 0 && days > max) return msg('validationMaxDays', max);
  return null;
});

/// Pickup lead-time validation — blokuje zpětnou rezervaci (čas v minulosti)
/// a vynucuje min. +6 h u přistavení (delivery). Shoduje se s webovým
/// `_rezMinPickupTime`. Vyzvednutí na pobočce = jen čas v budoucnosti.
final pickupLeadTimeValidationProvider = Provider<String?>((ref) {
  final draft = ref.watch(bookingDraftProvider);
  if (draft.startDate == null) return null;
  final moto = ref.watch(bookingMotoProvider);
  final lang = ref.watch(localeProvider).languageCode;
  return BookingValidator.checkPickupLeadTime(
    startDate: draft.startDate,
    pickupTime: draft.pickupTime,
    isDelivery: draft.pickupMethod == 'delivery',
    branchType: moto?.branchType,
    lang: lang,
  );
});

/// Combined booking validation error (license + overlap + délka pronájmu +
/// lead time vyzvednutí). Returns null if everything is OK.
final bookingValidationErrorProvider = Provider<String?>((ref) {
  return ref.watch(licenseValidationProvider) ??
      ref.watch(overlapValidationProvider) ??
      ref.watch(rentalLengthValidationProvider) ??
      ref.watch(pickupLeadTimeValidationProvider);
});

/// Povinné údaje profilu před rezervací (2026-08-22): adresa (ulice, město,
/// PSČ) VŽDY; číslo + platnost ŘP jen když motorka vyžaduje ŘP (ne dětské /
/// 'N'). Foto dokladů povinné NENÍ — lze doplnit dodatečně. Vrací
/// lokalizovanou hlášku s výčtem chybějících polí (formulář k ní přidá
/// tlačítko „Doplnit v profilu"), null = vše vyplněno. Stejná kontrola běží
/// i v payment_screen před insertem rezervace (pojistka).
final profileCompletenessValidationProvider = Provider<String?>((ref) {
  final moto = ref.watch(bookingMotoProvider);
  final profile = ref.watch(profileProvider).valueOrNull;
  // Profil se ještě načítá / nepřihlášený uživatel — gate řeší login flow;
  // po načtení profilu se provider přepočítá.
  if (profile == null) return null;
  final lang = ref.watch(localeProvider).languageCode;
  String trKey(String key) =>
      translations[lang]?[key] ?? translations['cs']?[key] ?? key;
  String val(String k) => (profile[k] ?? '').toString().trim();

  final needsLicense =
      !(moto?.licenseGroupsOrFallback.map((g) => g.toUpperCase()).contains('N') ??
          true);

  final missing = <String>[];
  if (val('street').isEmpty) missing.add(trKey('streetShort'));
  if (val('city').isEmpty) missing.add(trKey('city'));
  if (val('zip').isEmpty) missing.add(trKey('zip'));
  if (needsLicense) {
    if (val('license_number').isEmpty) missing.add(trKey('licenseNumber'));
    if (val('license_expiry').isEmpty) missing.add(trKey('licenseExpiry'));
  }
  if (missing.isNotEmpty) {
    return trKey('validationMissingProfile')
        .replaceAll('{fields}', missing.join(', '));
  }

  // Platnost ŘP nesmí skončit před koncem pronájmu (bez termínu: před dneškem).
  if (needsLicense) {
    final exp = DateTime.tryParse(val('license_expiry'));
    if (exp != null) {
      final draft = ref.watch(bookingDraftProvider);
      final limit = draft.endDate ?? DateTime.now();
      if (exp.isBefore(DateTime(limit.year, limit.month, limit.day))) {
        return trKey('validationLicenseExpired');
      }
    }
  }
  return null;
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

/// Dostupnost vozíku (příslušenství „Vozík") pro daný termín. count = počet
/// volných kusů, trailerId = první volný kus k přiřazení. Backend RPC
/// `get_trailer_availability` počítá obsazenost z přímých rezervací (moto_id)
/// i z gear-přiřazení (trailer_moto_id) + servisu.
class TrailerAvailability {
  final int count;
  final String? trailerId;
  const TrailerAvailability(this.count, this.trailerId);
  bool get hasFree => count > 0 && trailerId != null;
}

final trailerAvailabilityProvider = FutureProvider.family<TrailerAvailability,
    ({DateTime? start, DateTime? end})>((ref, range) async {
  final s = range.start, e = range.end;
  if (s == null || e == null) return const TrailerAvailability(0, null);
  String d(DateTime x) =>
      '${x.year.toString().padLeft(4, '0')}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
  try {
    final res = await MotoGoSupabase.client.rpc('get_trailer_availability',
        params: {'p_start': d(s), 'p_end': d(e)});
    final m = res as Map<String, dynamic>?;
    if (m == null) return const TrailerAvailability(0, null);
    return TrailerAvailability(
        (m['available_count'] as num?)?.toInt() ?? 0, m['trailer_id'] as String?);
  } catch (_) {
    return const TrailerAvailability(0, null);
  }
});
