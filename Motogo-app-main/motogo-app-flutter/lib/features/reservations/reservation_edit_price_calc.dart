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

  /// Aktuální věrnostní rank (loyalty level). Od [loyaltyFreeGearLevel] je
  /// veškerá placená výbava (výbava i obuv spolujezdce/řidiče) ZDARMA — i při
  /// úpravě rezervace.
  final int loyaltyLevel;

  /// Aktuální věrnostní sleva v % dle ranku — aplikuje se na KLADNÝ rozdíl
  /// (doplatek za pronájem + výbavu, bez dopravy) při úpravě APP rezervace.
  /// Screen ji předává jen pro booking_source='app', jinak 0 (parita se
  /// serverem: _apply_booking_changes_core / split_booking_moto_swap).
  final int loyaltyPercent;

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
    this.loyaltyLevel = 0,
    this.loyaltyPercent = 0,
  });

  static const _extraPrices = {'spolujezdec': 690.0, 'boty_ridic': 290.0, 'boty_spolujezdec': 290.0};

  /// Od 3. ranku je veškerá placená výbava (vč. obuvi a výbavy spolujezdce)
  /// zdarma — všechny položky v [_extraPrices] jsou gear.
  bool get _gearFree => loyaltyLevel >= loyaltyFreeGearLevel;

  double _priceFor(String id) => _gearFree ? 0.0 : (_extraPrices[id] ?? 0);

  /// Cena aktuálně vybraných doplňků.
  double get extrasTotal =>
      selectedExtras.fold(0.0, (sum, id) => sum + _priceFor(id));

  /// Cena původně zaplacených doplňků (baseline).
  double get origExtrasTotal =>
      origExtras.fold(0.0, (sum, id) => sum + _priceFor(id));

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

  /// Hrubá cena pronájmu původního rozsahu (ceník staré motorky).
  double get _rentalGrossOld => motoPrices != null
      ? motoPrices!.totalForRange(booking.startDate, booking.endDate)
      : origDailyPrice * origDays;

  /// Hrubá cena pronájmu nového rozsahu (ceník efektivní motorky — při výměně
  /// nové, jinak staré).
  double get _rentalGrossNew {
    if (newStart == null || newEnd == null) return _rentalGrossOld;
    final p = _effPrices;
    if (p != null) return p.totalForRange(newStart!, newEnd!);
    return origDailyPrice * newDays;
  }

  /// Informativní řádek UI: hrubý rozdíl pronájmu (bez storna a late slevy) —
  /// finální Doplatek/Vrácení počítá [rentalDiff]/[effectivePriceDiff].
  double get dateChangeAmount {
    if (newStart == null || newEnd == null) return 0;
    return _rentalGrossNew - _rentalGrossOld;
  }

  /// Storno % pro vratkovou část — server (_apply_booking_changes_core) ho
  /// počítá z NOVÉHO STARTU (v_fs), ne z konce. Vč. stropu po posunu termínu.
  int get stornoPercent =>
      StornoCalc.effectiveRefundPercent(newStart ?? booking.startDate, booking);

  /// Rozdíl pronájmu vč. late-pickup slevy — zrcadlí server:
  /// v_dates_diff = (nová hrubá − nová late) − (stará hrubá − stará late);
  /// ZÁPORNÝ rozdíl (vratka) se krátí storno % (i ztráta/zisk půldne podléhá
  /// stornu společně se zkrácenými dny), kladný doplatek je vždy 100 %.
  double get rentalDiff {
    if (newStart == null || newEnd == null) return 0;
    var d = (_rentalGrossNew - newLatePickup) - (_rentalGrossOld - oldLatePickup);
    if (d < 0) d = (d * stornoPercent / 100).roundToDouble();
    return d;
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

  /// Původní sleva na 1. den — REÁLNĚ uložená hodnota (ne přepočet; jinak by
  /// rezervace bez uložené late slevy vykázala fantomový rozdíl při úpravě).
  double get oldLatePickup => booking.latePickupDiscount ?? 0;

  /// Nová sleva na 1. den (po úpravě dat / motorky / času vyzvednutí).
  /// Bez načteného ceníku motorky nelze slevu přepočítat — drží se uložená
  /// hodnota (jinak by výpadek načtení ceníku vytvořil fantomový doplatek
  /// +oldLatePickup a tichý reset sloupce na 0).
  double get newLatePickup {
    if (newStart == null || newEnd == null) return 0;
    final p = _effPrices;
    if (p == null) return oldLatePickup;
    return _lateFor(p, newStart!, newEnd!, pickupTime);
  }

  /// Dopad změny late slevy na cenu (kladný = zákazník platí víc — o slevu
  /// přišel; záporný = slevu získal). Jen pro zobrazení řádku v UI.
  double get latePickupDelta => oldLatePickup - newLatePickup;

  double get priceDiff {
    if (newStart == null || newEnd == null) return 0;
    // rentalDiff už obsahuje rozdíl ceníku (vč. výměny motorky), late-pickup
    // slevu i storno na záporné části — zrcadlí server, viz výše.
    return rentalDiff + deliveryFeeDelta + extrasDelta;
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
    // DOPLATEK (gross >= 0): plná cena, sleva zachována (option B).
    if (priceDiff >= 0) return _oldDiscount;
    // VRATKA: uniformní poměrná sazba — procento i voucher se krátí stejně.
    if (_oldGross > 0) return (newGross * _oldDiscount / _oldGross).roundToDouble();
    return 0;
  }

  // ── Věrnostní sleva na doplatek (2026-08-06) ──
  // Kladný rozdíl pronájmu + výbavy (bez dopravy — parita se vznikem rezervace,
  // kde loyalty base = pronájem + výbava) se snižuje o % dle aktuálního ranku.
  // Vratky se nemění. Zrcadlí SQL _apply_booking_changes_core.

  /// Část rozdílu podléhající věrnostní slevě — doprava se vyjímá.
  double get _loyaltyEligibleDiff {
    final d = priceDiff - deliveryFeeDelta;
    return d > 0 ? d : 0;
  }

  /// Věrnostní sleva na doplatek v Kč — přičítá se k bookings.loyalty_discount_amount.
  double get loyaltySurchargeDiscount {
    if (loyaltyPercent <= 0) return 0;
    return (_loyaltyEligibleDiff * loyaltyPercent / 100).roundToDouble();
  }

  /// Nová celková cena (netto, po slevě) — ukládá se do bookings.total_price.
  double get newTotal {
    final t = newGross - newDiscountAmount - loyaltySurchargeDiscount;
    return t > 0 ? t.roundToDouble() : 0;
  }

  /// Rozdíl PO slevě — tohle se účtuje bránou (>0) nebo vrací refundem (<0).
  double get effectivePriceDiff => newTotal - booking.totalPrice;

  bool get hasChanges =>
      diffDays != 0 ||
      (newMotoId != null && newMotoId != booking.motoId) ||
      // Metody sémanticky (pobočka↔adresa) — DB drží synonyma pobočky
      // ('store'/'pickup'/'branch'/'rental'), obrazovka normalizuje na store.
      (pickupMethod == 'delivery') != (booking.pickupMethod == 'delivery') ||
      (returnMethod == 'delivery') != (booking.returnMethod == 'delivery') ||
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
