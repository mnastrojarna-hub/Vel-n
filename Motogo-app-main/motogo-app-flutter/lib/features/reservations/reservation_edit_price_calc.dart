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
  /// Původně zaplacené doplňky — účtuje/vrací se jen ROZDÍL vůči nim.
  final Set<String> origExtras;
  final String pickupMethod;
  final String returnMethod;
  final String pickupTime;
  final String returnTime;
  final String? helmetSize, jacketSize, pantsSize, bootsSize, glovesSize;
  final String? passengerHelmetSize, passengerJacketSize, passengerPantsSize, passengerBootsSize;

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
    this.origExtras = const {},
    required this.pickupMethod,
    required this.returnMethod,
    required this.pickupTime,
    required this.returnTime,
    this.helmetSize, this.jacketSize, this.pantsSize,
    this.bootsSize, this.glovesSize,
    this.passengerHelmetSize, this.passengerJacketSize, this.passengerPantsSize,
    this.passengerBootsSize,
    this.discountType,
  });

  static const _extraPrices = {'spolujezdec': 690.0, 'boty_ridic': 290.0, 'boty_spolujezdec': 290.0};

  /// Cena aktuálně vybraných doplňků.
  double get extrasTotal =>
      selectedExtras.fold(0.0, (sum, id) => sum + (_extraPrices[id] ?? 0));

  /// Cena původně zaplacených doplňků (baseline).
  double get origExtrasTotal =>
      origExtras.fold(0.0, (sum, id) => sum + (_extraPrices[id] ?? 0));

  /// ROZDÍL doplňků vůči původním — kladný = doplatek, záporný = refund.
  double get extrasDelta => extrasTotal - origExtrasTotal;

  bool get extrasChanged => !(selectedExtras.length == origExtras.length &&
      selectedExtras.containsAll(origExtras));

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

  /// Rozdíl poplatku za přistavení/odvoz oproti původní rezervaci.
  ///
  /// Účtuje se (kladný) nebo vrací (záporný) JEN rozdíl — dřív se nově
  /// zadaná adresa přičítala celá (dvojí účtování při změně adresy) a
  /// zrušení doručení nic nevracelo. DB ukládá jen kombinovanou
  /// `delivery_fee`; původní rozdělení mezi přistavení a odvoz se odhaduje
  /// rovným dílem mezi strany, které doručení měly.
  double get deliveryFeeDelta {
    final oldFee = booking.deliveryFee ?? 0;
    final pickupWas = booking.pickupMethod == 'delivery';
    final returnWas = booking.returnMethod == 'delivery';
    final pickupIs = pickupMethod == 'delivery';
    final returnIs = returnMethod == 'delivery';

    // Způsob dopravy beze změny a žádná nově přepočtená adresa → beze změny.
    if (pickupWas == pickupIs &&
        returnWas == returnIs &&
        pickupDelivFee == 0 &&
        returnDelivFee == 0) {
      return 0;
    }

    final oldSides = (pickupWas ? 1 : 0) + (returnWas ? 1 : 0);
    final oldPerSide = oldSides > 0 ? oldFee / oldSides : 0.0;
    final oldPickupFee = pickupWas ? oldPerSide : 0.0;
    final oldReturnFee = returnWas ? oldPerSide : 0.0;

    // Nová fee za stranu: pobočka → 0; doručení s nově zadanou adresou →
    // nový výpočet; doručení beze změny adresy → původní hodnota zůstává.
    final newPickupFee =
        !pickupIs ? 0.0 : (pickupDelivFee > 0 ? pickupDelivFee : oldPickupFee);
    final newReturnFee =
        !returnIs ? 0.0 : (returnDelivFee > 0 ? returnDelivFee : oldReturnFee);
    return (newPickupFee + newReturnFee) - (oldPickupFee + oldReturnFee);
  }

  /// Nová kombinovaná delivery_fee po úpravě (ukládá se do bookings).
  double get newDeliveryFee {
    final v = (booking.deliveryFee ?? 0) + deliveryFeeDelta;
    return v > 0 ? v : 0;
  }

  // ── Sleva 50 % na 1. den (pozdní vyzvednutí >=12:00, rezervace >=2 dny) ──
  // Mirror SQL _late_pickup_discount(). Je to redukce hrubého pronájmu — do
  // priceDiff vstupuje jako (stará sleva − nová sleva): víc slevy = vratka,
  // míň slevy (např. posun času před 12:00) = doplatek.
  static bool _isLatePickup(String? t) {
    if (t == null) return false;
    final p = t.split(':');
    final h = p.isNotEmpty ? int.tryParse(p[0]) : null;
    return h != null && h >= 12;
  }

  double _lateFor(DayPrices? prices, DateTime start, DateTime end, String? time) {
    if (prices == null) return 0;
    final d = end.difference(start).inDays + 1;
    if (d < 2 || !_isLatePickup(time)) return 0;
    return (prices.forWeekday(start.weekday) * 0.5).roundToDouble();
  }

  DayPrices? get _effPrices =>
      (newMotoId != null && newMotoId != booking.motoId && newMotoPrices != null)
          ? newMotoPrices
          : motoPrices;

  /// Původní sleva na 1. den (z původních dat a původního času vyzvednutí).
  double get oldLatePickup =>
      _lateFor(motoPrices, booking.startDate, booking.endDate, booking.pickupTime ?? '09:00');

  /// Nová sleva na 1. den (po úpravě dat / motorky / času vyzvednutí).
  double get newLatePickup {
    if (newStart == null || newEnd == null) return 0;
    return _lateFor(_effPrices, newStart!, newEnd!, pickupTime);
  }

  double get priceDiff {
    if (newStart == null || newEnd == null) return 0;
    double diff = dateChangeAmount;
    diff += deliveryFeeDelta;
    diff += extrasDelta;
    if (newMotoId != null && newMotoId != booking.motoId && newMotoPrices != null) {
      final newTotal = newMotoPrices!.totalForRange(newStart!, newEnd!);
      final origTotal = motoPrices?.totalForRange(newStart!, newEnd!)
          ?? (origDailyPrice * newDays);
      diff += newTotal - origTotal;
    }
    // Sleva 50 % na 1. den — víc slevy snižuje cenu (vratka), míň zvyšuje (doplatek).
    diff += oldLatePickup - newLatePickup;
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
      extrasChanged ||
      deliveryFeeDelta != 0 ||
      helmetSize != booking.helmetSize ||
      jacketSize != booking.jacketSize ||
      pantsSize != booking.pantsSize ||
      bootsSize != booking.bootsSize ||
      glovesSize != booking.glovesSize ||
      passengerHelmetSize != booking.passengerHelmetSize ||
      passengerJacketSize != booking.passengerJacketSize ||
      passengerPantsSize != booking.passengerPantsSize ||
      passengerBootsSize != booking.passengerBootsSize;
}
