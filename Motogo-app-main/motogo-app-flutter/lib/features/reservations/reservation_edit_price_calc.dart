import '../booking/booking_models.dart';
import '../catalog/moto_model.dart';
import 'reservation_models.dart';

/// Pure price calculation logic for reservation editing.
class EditPriceCalc {
  final Reservation booking;
  final DateTime? newStart;
  final DateTime? newEnd;
  final DayPrices? motoPrices;
  final String? newMotoId;
  final DayPrices? newMotoPrices;
  final double pickupDelivFee;
  final double returnDelivFee;
  final Set<String> selectedExtras;
  final String pickupMethod;
  final String returnMethod;
  final String pickupTime;
  final String returnTime;
  final String? helmetSize, jacketSize, pantsSize, bootsSize, glovesSize;
  final String? passengerHelmetSize, passengerJacketSize, passengerPantsSize;

  /// Typ slevy rezervace: 'percent' | 'fixed' | null (bez slevy / neznámý →
  /// chová se jako fixed). Načítá screen z promo_codes podle discount_code;
  /// voucher kódy v promo_codes nejsou → fixed.
  final String? discountType;

  const EditPriceCalc({
    required this.booking,
    required this.newStart,
    required this.newEnd,
    required this.motoPrices,
    required this.newMotoId,
    this.newMotoPrices,
    required this.pickupDelivFee,
    required this.returnDelivFee,
    required this.selectedExtras,
    required this.pickupMethod,
    required this.returnMethod,
    required this.pickupTime,
    required this.returnTime,
    this.helmetSize, this.jacketSize, this.pantsSize,
    this.bootsSize, this.glovesSize,
    this.passengerHelmetSize, this.passengerJacketSize, this.passengerPantsSize,
    this.discountType,
  });

  double get extrasTotal {
    // Ceny dle webu (accessory_types): passenger_gear=690, boty=290.
    const prices = {'spolujezdec': 690.0, 'boty_ridic': 290.0, 'boty_spolujezdec': 290.0};
    return selectedExtras.fold(0.0, (sum, id) => sum + (prices[id] ?? 0));
  }

  int get origDays => booking.dayCount;
  int get newDays {
    if (newStart == null || newEnd == null) return origDays;
    return newEnd!.difference(newStart!).inDays + 1;
  }
  int get diffDays => newDays - origDays;

  double get origDailyPrice {
    if (origDays == 0) return 0;
    final base = booking.totalPrice
        + (booking.discountAmount ?? 0)
        - (booking.deliveryFee ?? 0)
        - (booking.extrasPrice ?? 0);
    return base / origDays;
  }

  double get dateChangeAmount {
    if (diffDays == 0 || newStart == null || newEnd == null) return 0;
    if (motoPrices != null) {
      final origRange = motoPrices!.totalForRange(booking.startDate, booking.endDate);
      final newRange = motoPrices!.totalForRange(newStart!, newEnd!);
      if (diffDays > 0) {
        return newRange - origRange;
      } else {
        final raw = origRange - newRange;
        final pct = StornoCalc.refundPercent(newEnd!);
        return -(raw * pct / 100);
      }
    }
    if (diffDays > 0) return diffDays * origDailyPrice;
    final raw = diffDays.abs() * origDailyPrice;
    final pct = StornoCalc.refundPercent(newEnd ?? booking.endDate);
    return -(raw * pct / 100);
  }

  double get priceDiff {
    if (newStart == null || newEnd == null) return 0;
    double diff = dateChangeAmount;
    diff += pickupDelivFee + returnDelivFee;
    diff += extrasTotal;
    if (newMotoId != null && newMotoId != booking.motoId && newMotoPrices != null) {
      final newTotal = newMotoPrices!.totalForRange(newStart!, newEnd!);
      final origTotal = motoPrices?.totalForRange(newStart!, newEnd!)
          ?? (origDailyPrice * newDays);
      diff += newTotal - origTotal;
    }
    return diff;
  }

  // ── Varianta B (2026-06-11): sleva se přepočítá na nový obsah rezervace ──
  // `priceDiff` je HRUBÝ rozdíl (po stornu na zkrácené části). Na novou hrubou
  // cenu se znovu aplikuje původní sleva: procentuální efektivní sazbou
  // (discount / stará hrubá), absolutní jako odpočet max do výše nové hrubé.
  // Účtuje/vrací se `effectivePriceDiff` (po slevě) — zrcadlí SQL helper
  // _apply_discount_variant_b (web RPC cesty počítají totéž server-side).

  double get _oldDiscount {
    final d = booking.discountAmount ?? 0.0;
    return d > 0 ? d : 0.0;
  }

  double get _oldGross => booking.totalPrice + _oldDiscount;

  double get newGross {
    final g = _oldGross + priceDiff;
    return g > 0 ? g : 0;
  }

  /// Nová výše slevy v Kč po úpravě — ukládá se do bookings.discount_amount.
  double get newDiscountAmount {
    if (_oldDiscount <= 0) return 0;
    if (discountType == 'percent' && _oldGross > 0) {
      return (newGross * _oldDiscount / _oldGross).roundToDouble();
    }
    return _oldDiscount > newGross ? newGross : _oldDiscount;
  }

  /// Nová celková cena (netto, po slevě) — ukládá se do bookings.total_price.
  double get newTotal {
    final t = newGross - newDiscountAmount;
    return t > 0 ? t.roundToDouble() : 0;
  }

  /// Rozdíl PO slevě — tohle se účtuje bránou (>0) nebo vrací refundem (<0).
  double get effectivePriceDiff => newTotal - booking.totalPrice;

  bool get hasChanges =>
      diffDays != 0 ||
      (newMotoId != null && newMotoId != booking.motoId) ||
      pickupMethod != booking.pickupMethod ||
      returnMethod != booking.returnMethod ||
      pickupTime != (booking.pickupTime ?? '09:00') ||
      returnTime != (booking.returnTime ?? '19:00') ||
      extrasTotal > 0 ||
      pickupDelivFee > 0 ||
      returnDelivFee > 0 ||
      helmetSize != booking.helmetSize ||
      jacketSize != booking.jacketSize ||
      pantsSize != booking.pantsSize ||
      bootsSize != booking.bootsSize ||
      glovesSize != booking.glovesSize ||
      passengerHelmetSize != booking.passengerHelmetSize ||
      passengerJacketSize != booking.passengerJacketSize ||
      passengerPantsSize != booking.passengerPantsSize;
}
